"""Thin wrapper around pymobiledevice3 (9.x) for iOS 17+ location simulation.

The wrapper hides three things from the rest of the sidecar:
  1. Tunneld discovery (RemoteServiceDiscoveryService over the local tunneld HTTP API).
  2. Mounter handling (personalized DDI auto-mount on first connect).
  3. DVT location-simulation lifecycle (set / clear, with reconnect on stale handles).

Everything that talks to pymobiledevice3 lives here; if the upstream API moves,
this is the only file that needs to follow.

pymobiledevice3 9.x notes:
  - tunneld discovery: `pymobiledevice3.tunneld.api.get_tunneld_devices()` (sync).
  - DDI mount: `auto_mount_personalized` is async — drive on the persistent loop.
  - DVT: `DvtProvider` (formerly `DvtSecureSocketProxyService`) — async ctx mgr.
  - LocationSimulation: async ctx mgr; `set` and `clear` are async.
"""

from __future__ import annotations

import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from typing import Any

MOUNT_TIMEOUT_S = 90.0  # personalized DDI mount on iOS 26 sometimes hangs; fail loud instead.
MOUNT_QUERY_TIMEOUT_S = 10.0  # checking "already mounted?" should be near-instant.


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
        self._rsd: Any = None  # RemoteServiceDiscoveryService
        self._dvt: Any = None  # DvtProvider (entered)
        self._loc: Any = None  # LocationSimulation (entered)
        self._dvt_cm: Any = None  # async ctx mgr handle, for __aexit__
        self._loc_cm: Any = None
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
                self._run_async(self._loc.set(lat, lon))
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
                self._run_async(self._loc.clear())
                log.info("clear_location: simulation stopped")
            except Exception:
                log.exception("clear_location failed (ignored, real GPS will time out)")
                self._reset()

    def shutdown(self) -> None:
        """Best-effort cleanup on sidecar exit."""
        with self._lock:
            try:
                self.clear_location()
            finally:
                self._reset()

    # ------------------------------------------------------------------ internal

    @staticmethod
    def _run_async(coro):
        """Drive a coroutine on pymobiledevice3's persistent asyncio loop."""
        from pymobiledevice3.utils import get_asyncio_loop

        return get_asyncio_loop().run_until_complete(coro)

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

        t1 = time.monotonic()
        self._open_dvt_session(rsd)
        log.info("DVT session open (%.2fs)", time.monotonic() - t1)

        self._rsd = rsd
        self._info = info

        log.info(
            "session ready: udid=%s name=%s ios=%s (total %.2fs)",
            info.udid, info.name, info.ios_version, time.monotonic() - t0,
        )

    def _discover_device(self):
        """Hit the local tunneld HTTP API and pick the first device."""
        try:
            from pymobiledevice3.remote.remote_service_discovery import (
                RemoteServiceDiscoveryService,
            )
            from pymobiledevice3.tunneld.api import get_tunneld_devices
        except ImportError as e:
            raise TunneldUnreachableError(f"pymobiledevice3 import failed: {e}") from e

        try:
            # 9.x: get_tunneld_devices is async (no sync wrapper). Drive on the
            # persistent loop so the returned RSD's tasks stay on the same one.
            devices = self._run_async(get_tunneld_devices())
        except Exception as e:
            raise TunneldUnreachableError(
                f"tunneld unreachable — is `sudo pymobiledevice3 remote tunneld` running? ({e})"
            ) from e

        if not devices:
            raise NoDeviceError("tunneld reports no connected iPhone")

        first = devices[0]
        if isinstance(first, RemoteServiceDiscoveryService):
            return first
        # Defensive — older tunneld returned (host, port) tuples. 9.x returns RSD instances.
        if isinstance(first, tuple) and len(first) == 2:
            host, port = first
            rsd = RemoteServiceDiscoveryService((host, port))
            self._run_async(rsd.connect())
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
        """Mount the personalized Developer Disk Image once per UDID.

        Strategy:
          1. Skip if this DeviceManager has already mounted for this UDID.
          2. Skip if the iPhone reports the Personalized image already mounted
             (e.g. Xcode mounted it during pairing). iOS 26 mount via
             auto_mount_personalized is flaky, so reusing Xcode's mount is faster
             and more reliable when available.
          3. Otherwise call auto_mount_personalized with a hard timeout — iOS 26
             can hang the TSS / mount step indefinitely.
        """
        if self._mounted_for_udid == udid:
            log.debug("DDI already mounted (cached) for udid=%s", udid)
            return

        if self._is_already_mounted_on_device(rsd):
            log.info("personalized DDI already mounted on iPhone (likely by Xcode) — skipping mount")
            self._mounted_for_udid = udid
            return

        from pymobiledevice3.services.mobile_image_mounter import auto_mount_personalized

        log.info(
            "mounting personalized DDI for udid=%s "
            "(first run downloads ~10MB + signs via Apple TSS, can take 10–60s; "
            "hard timeout %.0fs)",
            udid, MOUNT_TIMEOUT_S,
        )
        t0 = time.monotonic()
        try:
            self._run_async(asyncio.wait_for(auto_mount_personalized(rsd), MOUNT_TIMEOUT_S))
            self._mounted_for_udid = udid
            log.info("DDI mount ok (%.2fs)", time.monotonic() - t0)
        except asyncio.TimeoutError as e:
            log.error(
                "DDI mount timed out after %.0fs — iOS 26 personalized DDI can hang. "
                "Workaround: open Xcode → Window → Devices and Simulators, wait until "
                "your iPhone shows green, then retry. Xcode mounts the DDI itself and "
                "this sidecar will reuse that mount.",
                MOUNT_TIMEOUT_S,
            )
            raise MounterError(
                f"personalized DDI auto-mount timed out after {MOUNT_TIMEOUT_S:.0f}s "
                f"— try Xcode auto-mount first"
            ) from e
        except Exception as e:
            log.exception("DDI mount failed after %.2fs", time.monotonic() - t0)
            raise MounterError(
                f"personalized DDI auto-mount failed: {type(e).__name__}: {e}"
            ) from e

    def _is_already_mounted_on_device(self, rsd) -> bool:
        """Ask the iPhone whether the Personalized DDI is currently mounted.

        Returns False on any failure — caller will then attempt the mount path,
        which has its own error handling. This is purely an optimization /
        workaround for iOS 26 mounter flakiness.
        """
        from pymobiledevice3.services.mobile_image_mounter import (
            MobileImageMounterService,
            PersonalizedImageMounter,
        )

        async def _query() -> bool:
            async with MobileImageMounterService(lockdown=rsd) as svc:
                return await svc.is_image_mounted(PersonalizedImageMounter.IMAGE_TYPE)

        try:
            return self._run_async(asyncio.wait_for(_query(), MOUNT_QUERY_TIMEOUT_S))
        except Exception as e:
            log.warning(
                "could not query existing DDI mount state (will attempt mount anyway): %s: %s",
                type(e).__name__, e,
            )
            return False

    def _open_dvt_session(self, rsd) -> None:
        """Enter DvtProvider + LocationSimulation as async context managers."""
        from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
        from pymobiledevice3.services.dvt.instruments.location_simulation import (
            LocationSimulation,
        )

        dvt_cm = DvtProvider(rsd)
        dvt = self._run_async(dvt_cm.__aenter__())
        try:
            loc_cm = LocationSimulation(dvt)
            loc = self._run_async(loc_cm.__aenter__())
        except Exception:
            # Roll back the DVT context if LocationSimulation entry fails.
            try:
                self._run_async(dvt_cm.__aexit__(None, None, None))
            except Exception:
                log.debug("aexit on DvtProvider during rollback raised", exc_info=True)
            raise

        self._dvt_cm, self._dvt = dvt_cm, dvt
        self._loc_cm, self._loc = loc_cm, loc

    def _reset(self) -> None:
        """Drop cached handles so the next call re-discovers the device."""
        if self._info is not None:
            log.info("dropping session for udid=%s", self._info.udid)

        # Exit async context managers in reverse order (LocationSimulation first).
        for cm in (self._loc_cm, self._dvt_cm):
            if cm is None:
                continue
            try:
                self._run_async(cm.__aexit__(None, None, None))
            except Exception:
                log.debug("aexit on %s raised", type(cm).__name__, exc_info=True)

        # RSD has a sync close.
        if self._rsd is not None:
            for closer_attr in ("close", "stop"):
                fn = getattr(self._rsd, closer_attr, None)
                if callable(fn):
                    try:
                        fn()
                    except Exception:
                        log.debug("close on RSD raised", exc_info=True)
                    break

        self._rsd = None
        self._dvt = None
        self._loc = None
        self._dvt_cm = None
        self._loc_cm = None
        self._info = None
        # Keep _mounted_for_udid — DDI mount survives RSD reconnects.
