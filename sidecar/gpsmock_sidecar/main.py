"""FastAPI sidecar: bind 127.0.0.1:5555, expose 6 endpoints, clean up on signal."""

from __future__ import annotations

import logging
import os
import signal
import socket
import sys
from contextlib import asynccontextmanager

import uvicorn
from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

from . import __version__
from .device import (
    DeviceManager,
    MounterError,
    NoDeviceError,
    TunneldUnreachableError,
)
from .walker import Walker

log = logging.getLogger(__name__)

HOST = "127.0.0.1"
PORT = 5555

# Single source of truth for log formatting. Both stdlib and uvicorn loggers
# render lines this way so the console is uniform.
LOG_FORMAT = "%(asctime)s %(levelname)-7s %(name)s: %(message)s"
LOG_DATEFMT = "%Y-%m-%d %H:%M:%S"


# ---------------------------------------------------------------- DTOs


class TeleportBody(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)


class WalkBody(BaseModel):
    points: list[tuple[float, float]]
    speed_mps: float = Field(..., gt=0, le=10)

    @field_validator("points")
    @classmethod
    def _check_points(cls, v: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if len(v) < 2:
            raise ValueError("walk requires at least 2 points")
        for lat, lon in v:
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                raise ValueError(f"point out of range: ({lat}, {lon})")
        return v


# ---------------------------------------------------------------- app factory


def create_app(device: DeviceManager | None = None) -> FastAPI:
    """Build the FastAPI app. The `device` arg is the seam for tests."""
    device = device or DeviceManager()
    walker = Walker(push=device.set_location)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        log.info("sidecar v%s listening on http://%s:%d", __version__, HOST, PORT)
        try:
            yield
        finally:
            log.info("sidecar shutting down — clearing device")
            walker.cancel()
            device.shutdown()

    app = FastAPI(title="GPSMock sidecar", version=__version__, lifespan=lifespan)
    app.state.device = device
    app.state.walker = walker

    # ------------------------------------------------------------ endpoints

    def _device_dep() -> DeviceManager:
        return app.state.device

    def _walker_dep() -> Walker:
        return app.state.walker

    @app.get("/health")
    def health() -> dict:
        return {"ok": True, "version": __version__}

    @app.get("/device")
    def device_info(d: DeviceManager = Depends(_device_dep)) -> JSONResponse:
        try:
            info = d.get_device_info()
        except TunneldUnreachableError as e:
            log.warning("/device: tunneld unreachable — %s", e)
            return JSONResponse(
                {"error": "tunneld_unreachable", "detail": str(e)}, status_code=503
            )
        except NoDeviceError as e:
            log.warning("/device: no device — %s", e)
            return JSONResponse(
                {"error": "no_device", "detail": str(e)}, status_code=404
            )
        except MounterError as e:
            log.error("/device: mounter failed — %s", e)
            return JSONResponse(
                {"error": "mounter_failed", "detail": str(e)}, status_code=503
            )
        return JSONResponse(info.to_dict(), status_code=200)

    @app.post("/teleport")
    def teleport(
        body: TeleportBody,
        d: DeviceManager = Depends(_device_dep),
        w: Walker = Depends(_walker_dep),
    ) -> JSONResponse:
        log.info("/teleport lat=%.6f lon=%.6f", body.lat, body.lon)
        try:
            w.cancel()
            d.set_location(body.lat, body.lon)
            w.set_current_static((body.lat, body.lon))
        except TunneldUnreachableError as e:
            log.warning("/teleport: tunneld unreachable — %s", e)
            return JSONResponse({"error": "tunneld_unreachable", "detail": str(e)}, 503)
        except NoDeviceError as e:
            log.warning("/teleport: no device — %s", e)
            return JSONResponse({"error": "no_device", "detail": str(e)}, 503)
        except MounterError as e:
            log.error("/teleport: mounter failed — %s", e)
            return JSONResponse({"error": "mounter_failed", "detail": str(e)}, 503)
        return JSONResponse({"ok": True}, status_code=200)

    @app.post("/walk", status_code=202)
    def walk(
        body: WalkBody,
        d: DeviceManager = Depends(_device_dep),
        w: Walker = Depends(_walker_dep),
    ) -> dict:
        log.info(
            "/walk points=%d speed=%.2f m/s start=(%.6f,%.6f) end=(%.6f,%.6f)",
            len(body.points), body.speed_mps,
            body.points[0][0], body.points[0][1],
            body.points[-1][0], body.points[-1][1],
        )
        try:
            d.get_device_info()  # confirms connectivity before kicking off walker
        except TunneldUnreachableError as e:
            log.warning("/walk: tunneld unreachable — %s", e)
            raise HTTPException(503, {"error": "tunneld_unreachable", "detail": str(e)})
        except NoDeviceError as e:
            log.warning("/walk: no device — %s", e)
            raise HTTPException(503, {"error": "no_device", "detail": str(e)})
        except MounterError as e:
            log.error("/walk: mounter failed — %s", e)
            raise HTTPException(503, {"error": "mounter_failed", "detail": str(e)})

        try:
            w.start(body.points, body.speed_mps)
        except ValueError as e:
            log.warning("/walk: invalid input — %s", e)
            raise HTTPException(400, str(e))
        return {"ok": True}

    @app.post("/clear")
    def clear(
        d: DeviceManager = Depends(_device_dep),
        w: Walker = Depends(_walker_dep),
    ) -> dict:
        log.info("/clear")
        w.cancel()
        # clear_location is best-effort; never block /clear on it.
        try:
            d.clear_location()
        except DeviceErrorIgnored:
            pass
        w.set_current_static(None)
        return {"ok": True}

    @app.get("/status")
    def status(w: Walker = Depends(_walker_dep)) -> dict:
        current, walking = w.state()
        return {
            "current": list(current) if current is not None else None,
            "walking": walking,
        }

    return app


class DeviceErrorIgnored(Exception):
    """Sentinel never raised — we always swallow clear_location() errors."""


# ---------------------------------------------------------------- entrypoint


def _check_port_free(host: str, port: int) -> None:
    """Refuse to start if the port is already in use, with a clear message."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind((host, port))
    except OSError as e:
        sys.stderr.write(
            f"error: cannot bind {host}:{port} — already in use ({e}). "
            f"Run `lsof -i :{port}` and stop the conflicting process.\n"
        )
        sys.exit(2)
    finally:
        s.close()


def _install_signal_handlers(app: FastAPI) -> None:
    """SIGTERM / SIGINT → cancel walker, clear device, exit within ~3 s."""

    def _shutdown(signum, _frame):
        log.warning("received signal %s, shutting down", signum)
        try:
            app.state.walker.cancel()
        except Exception:
            pass
        try:
            app.state.device.shutdown()
        except Exception:
            pass
        # uvicorn catches the signal too and will exit; this just makes sure we
        # cleared the device before its own shutdown sequence runs.

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, _shutdown)
        except (ValueError, OSError):
            # signal.signal only works on the main thread; tests/embedding may skip.
            pass


def _resolve_log_level() -> str:
    """Resolve log level from $GPSMOCK_LOG_LEVEL, defaulting to INFO."""
    raw = os.environ.get("GPSMOCK_LOG_LEVEL", "INFO").upper()
    if raw not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
        sys.stderr.write(f"warning: invalid GPSMOCK_LOG_LEVEL={raw!r}, falling back to INFO\n")
        return "INFO"
    return raw


def _uvicorn_log_config(level: str) -> dict:
    """Build a uvicorn LOGGING_CONFIG that matches our app loggers' format.

    Uvicorn's access records carry separate %(client_addr)s / %(request_line)s /
    %(status_code)s fields rather than a pre-rendered message — keep its
    AccessFormatter and just prepend our timestamp/level/name prefix.
    """
    access_fmt = (
        '%(asctime)s %(levelname)-7s %(name)s: '
        '%(client_addr)s - "%(request_line)s" %(status_code)s'
    )
    return {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {"format": LOG_FORMAT, "datefmt": LOG_DATEFMT},
            "access": {
                "()": "uvicorn.logging.AccessFormatter",
                "fmt": access_fmt,
                "datefmt": LOG_DATEFMT,
                "use_colors": False,
            },
        },
        "handlers": {
            "default": {
                "formatter": "default",
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stderr",
            },
            "access": {
                "formatter": "access",
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stdout",
            },
        },
        "loggers": {
            "uvicorn": {"handlers": ["default"], "level": level, "propagate": False},
            "uvicorn.error": {"level": level},
            "uvicorn.access": {"handlers": ["access"], "level": "INFO", "propagate": False},
        },
    }


def run() -> None:
    level = _resolve_log_level()
    logging.basicConfig(level=level, format=LOG_FORMAT, datefmt=LOG_DATEFMT)
    _check_port_free(HOST, PORT)
    app = create_app()
    _install_signal_handlers(app)
    uvicorn.run(app, host=HOST, port=PORT, log_config=_uvicorn_log_config(level))


if __name__ == "__main__":
    run()
