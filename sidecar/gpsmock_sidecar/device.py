"""Thin wrapper around pymobiledevice3 for iOS 17+ location simulation.

The wrapper hides three things from the rest of the sidecar:
  1. Tunneld discovery (RemoteServiceDiscoveryService over the local tunneld HTTP API).
  2. Mounter handling (personalized DDI auto-mount on first connect).
  3. DVT location-simulation lifecycle (set / clear, with reconnect on stale handles).

Everything that talks to pymobiledevice3 lives here; if the upstream API moves,
this is the only file that needs to follow.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass


log = logging.getLogger(__name__)


class DeviceError(Exception):
    """Base for all device-side errors surfaced to the HTTP layer."""


class TunneldUnreachableError(DeviceError):
    """The local tunneld daemon is not reachable (user forgot `sudo pymobiledevice3 remote tunneld`)."""


class NoDeviceError(DeviceError):
    """Tunneld is up but reports no connected iPhone."""


class MounterError(DeviceError):
    """Personalized Developer Disk Image mount failed; surface the message verbatim."""


@dataclass(frozen=True)
class DeviceInfo:
    udid: str
    name: str
    ios_version: str

    def to_dict(self) -> dict[str, str]:
        return {"udid": self.udid, "name": self.name, "ios_version": self.ios_version}


class DeviceManager:
    """Lazily acquires and caches a tunneld-backed RemoteXPC + DVT session.

    Thread-safe: all public methods acquire `self._lock`. The expected concurrency
    pattern is HTTP request handlers (FastAPI workers) plus the Walker thread —
    a single mutex is plenty.
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._rsd = None  # RemoteServiceDiscoveryService
        self._dvt = None  # DvtSecureSocketProxyService
        self._loc = None  # LocationSimulation
        self._info: DeviceInfo | None = None
        self._mounted_for_udid: str | None = None

    # ------------------------------------------------------------------ public

    def get_device_info(self) -> DeviceInfo:
        """Return cached device info, acquiring a session if needed.

        Raises:
            TunneldUnreachableError: tunneld is not running.
            NoDeviceError: tunneld is running but reports no device.
            MounterError: personalized DDI mount failed.
        """
        with self._lock:
            self._ensure_session()
            assert self._info is not None
            return self._info

    def set_location(self, lat: float, lon: float) -> None:
        """Push a single coordinate to the iPhone. Idempotent on repeat calls."""
        with self._lock:
            self._ensure_session()
            log.debug("set_location lat=%.6f lon=%.6f", lat, lon)
            try:
                self._loc.simulate_location(lat, lon)  # pymobiledevice3 4.x API
            except AttributeError:
                # Older pymobiledevice3 used .set(...). Be tolerant.
                self._loc.set(lat, lon)
            except Exception:
                log.exception("set_location failed, dropping session for retry")
                self._reset()
                raise

    def clear_location(self) -> None:
        """Stop simulation and let real GPS take over. Idempotent — safe to call when idle."""
        with self._lock:
            if self._loc is None:
                log.debug("clear_location: no active session, no-op")
                return
            try:
                # pymobiledevice3 exposes either .clear() or .stop(). Try both.
                clear = getattr(self._loc, "clear", None) or getattr(self._loc, "stop", None)
                if clear is None:
                    log.warning("LocationSimulation has no clear/stop method; skipping")
                    return
                clear()
                log.info("clear_location: simulation stopped")
            except Exception:
                log.exception("clear_location failed (ignored, real GPS will time out)")
                self._reset()

    # ------------------------------------------------------------------ internal

    def _ensure_session(self) -> None:
        """Acquire RSD + DVT + LocationSimulation if not already cached."""
        if self._loc is not None and self._info is not None:
            return

        log.info("acquiring device session")
        t0 = time.monotonic()

        rsd = self._discover_device()
        log.info("tunneld discovery ok (%.2fs)", time.monotonic() - t0)

        info = self._extract_info(rsd)

        self._auto_mount(rsd, info.udid)

        t2 = time.monotonic()
        dvt, loc = self._open_dvt(rsd)
        log.info("DVT handshake ok (%.2fs)", time.monotonic() - t2)

        self._rsd = rsd
        self._dvt = dvt
        self._loc = loc
        self._info = info

        log.info(
            "session ready: udid=%s name=%s ios=%s (total %.2fs)",
            info.udid, info.name, info.ios_version, time.monotonic() - t0,
        )

    def _discover_device(self):
        """Hit the local tunneld HTTP API and pick the first device.

        tunneld exposes a small JSON API (default port 49151) listing connected
        devices and their RemoteXPC tunnel addresses. We import lazily so import
        errors map to TunneldUnreachableError rather than crashing module load.
        """
        try:
            from pymobiledevice3.remote.remote_service_discovery import (
                RemoteServiceDiscoveryService,
            )

            # Prefer the sync wrapper — it uses pymobiledevice3's persistent
            # asyncio loop, so the RSD's underlying connection stays alive after
            # this call. asyncio.run() would close the loop and break the RSD.
            _get = None
            for path in (
                ("pymobiledevice3.tunneld.api", "get_tunneld_devices"),
                ("pymobiledevice3.tunneld", "get_tunneld_devices"),
            ):
                try:
                    mod = __import__(path[0], fromlist=[path[1]])
                    _get = getattr(mod, path[1])
                    break
                except (ImportError, AttributeError):
                    continue
            if _get is None:
                raise ImportError("no get_tunneld_devices found in pymobiledevice3.tunneld[.api]")
        except ImportError as e:
            raise TunneldUnreachableError(f"pymobiledevice3 import failed: {e}") from e

        try:
            devices = _get()
        except Exception as e:
            raise TunneldUnreachableError(
                f"tunneld unreachable — is `sudo pymobiledevice3 remote tunneld` running? ({e})"
            ) from e

        if not devices:
            raise NoDeviceError("tunneld reports no connected iPhone")

        first = devices[0]
        # Devices come back as either RSD instances or (host, port) tuples depending on version.
        if isinstance(first, RemoteServiceDiscoveryService):
            return first
        if isinstance(first, tuple) and len(first) == 2:
            host, port = first
            rsd = RemoteServiceDiscoveryService((host, port))
            rsd.connect()
            return rsd
        # Best-effort: assume it has .host / .port
        host = getattr(first, "host", None) or getattr(first, "address", None)
        port = getattr(first, "port", None)
        if host and port:
            rsd = RemoteServiceDiscoveryService((host, port))
            rsd.connect()
            return rsd
        raise TunneldUnreachableError(
            f"tunneld returned an unrecognized device record: {type(first).__name__}"
        )

    @staticmethod
    def _extract_info(rsd) -> DeviceInfo:
        # RSD typically exposes `udid`, `product_version`, and either `name` or
        # `product_name`. Fall back gracefully if a field is missing.
        udid = getattr(rsd, "udid", None) or getattr(rsd, "identifier", "unknown")
        name = (
            getattr(rsd, "name", None)
            or getattr(rsd, "device_name", None)
            or getattr(rsd, "product_name", None)
            or "iPhone"
        )
        ios_version = (
            getattr(rsd, "product_version", None)
            or getattr(rsd, "ios_version", None)
            or "unknown"
        )
        return DeviceInfo(udid=udid, name=name, ios_version=ios_version)

    def _auto_mount(self, rsd, udid: str) -> None:
        """Mount the personalized Developer Disk Image once per UDID."""
        if self._mounted_for_udid == udid:
            log.debug("DDI already mounted for udid=%s", udid)
            return
        try:
            from pymobiledevice3.services.mobile_image_mounter import (
                auto_mount_personalized,
            )
        except ImportError:
            # Older pymobiledevice3 versions called this differently or did it implicitly.
            log.info("auto_mount_personalized not available; skipping explicit mount")
            self._mounted_for_udid = udid
            return

        log.info("mounting personalized DDI for udid=%s (first run downloads ~10MB + signs via Apple TSS, can take 10–60s)", udid)
        t0 = time.monotonic()
        try:
            result = auto_mount_personalized(rsd)
            # pymobiledevice3 ≥4.x made this a coroutine. Drive it on the
            # library's persistent loop so the RSD's tasks stay on the same one.
            import inspect

            if inspect.iscoroutine(result):
                from pymobiledevice3.utils import get_asyncio_loop

                get_asyncio_loop().run_until_complete(result)
            self._mounted_for_udid = udid
            log.info("DDI mount ok (%.2fs)", time.monotonic() - t0)
        except Exception as e:
            log.exception("DDI mount failed after %.2fs", time.monotonic() - t0)
            raise MounterError(f"personalized DDI auto-mount failed: {e}") from e

    @staticmethod
    def _open_dvt(rsd):
        from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import (
            DvtSecureSocketProxyService,
        )
        from pymobiledevice3.services.dvt.instruments.location_simulation import (
            LocationSimulation,
        )

        dvt = DvtSecureSocketProxyService(lockdown=rsd)
        dvt.perform_handshake()
        loc = LocationSimulation(dvt)
        return dvt, loc

    def _reset(self) -> None:
        """Drop cached handles so the next call re-discovers the device."""
        if self._info is not None:
            log.info("dropping session for udid=%s", self._info.udid)
        for closer_attr in ("close", "stop"):
            for h in (self._loc, self._dvt, self._rsd):
                if h is None:
                    continue
                fn = getattr(h, closer_attr, None)
                if callable(fn):
                    try:
                        fn()
                    except Exception:
                        log.debug("close/stop on %s raised", type(h).__name__, exc_info=True)
        self._rsd = None
        self._dvt = None
        self._loc = None
        self._info = None
        # Keep _mounted_for_udid — DDI mount survives RSD reconnects.

    def shutdown(self) -> None:
        """Best-effort cleanup on sidecar exit."""
        with self._lock:
            try:
                self.clear_location()
            finally:
                self._reset()
