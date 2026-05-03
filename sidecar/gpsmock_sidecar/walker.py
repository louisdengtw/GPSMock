"""Walker — interpolates a polyline and pushes coordinates to the device at ~1 Hz.

Single-flight: starting a new walk cancels any active one cleanly. The active
walker runs on a daemon thread; the main thread (FastAPI handlers) reads
`state()` to answer `/status`.
"""

from __future__ import annotations

import logging
import math
import random
import threading
import time
from collections.abc import Callable, Sequence

log = logging.getLogger(__name__)

EARTH_RADIUS_M = 6_371_000.0
TICK_SECONDS = 1.0  # ~1 Hz updates
MAX_COORD_JITTER_M = 1.0  # cap per spec
SPEED_JITTER_RANGE = (0.85, 1.15)  # ±15% per-segment


# --------------------------------------------------------------------- math


def haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Great-circle distance in meters between two (lat, lon) points."""
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


def interpolate(
    a: tuple[float, float], b: tuple[float, float], t: float
) -> tuple[float, float]:
    """Linear interpolation in lat/lon space — fine for sub-km segments."""
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def jitter_coord(point: tuple[float, float], rng: random.Random) -> tuple[float, float]:
    """Add a small random offset capped at MAX_COORD_JITTER_M great-circle distance."""
    # 1 m of latitude ≈ 1 / 111320 degrees; 1 m of longitude scales with cos(lat).
    lat, lon = point
    max_deg_lat = MAX_COORD_JITTER_M / 111_320.0
    cos_lat = max(math.cos(math.radians(lat)), 1e-6)
    max_deg_lon = MAX_COORD_JITTER_M / (111_320.0 * cos_lat)
    # Sample inside a disk so the cap is never exceeded.
    r = rng.random() ** 0.5  # uniform-by-area
    theta = rng.uniform(0, 2 * math.pi)
    dlat = r * max_deg_lat * math.sin(theta)
    dlon = r * max_deg_lon * math.cos(theta)
    return (lat + dlat, lon + dlon)


# --------------------------------------------------------------------- walker


class Walker:
    """Single-flight polyline player.

    Args:
        push: callback that pushes a (lat, lon) to the device. Called on the
            walker thread. Must not block longer than ~100 ms.
        sleeper: function that sleeps for the requested seconds. Tests inject
            a fake clock; production uses time.sleep.
        rng: random source (tests inject seeded; production uses module-default).
    """

    def __init__(
        self,
        push: Callable[[float, float], None],
        sleeper: Callable[[float], None] = time.sleep,
        rng: random.Random | None = None,
    ) -> None:
        self._push = push
        self._sleep = sleeper
        self._rng = rng or random.Random()

        self._lock = threading.Lock()
        self._cancel = threading.Event()
        self._thread: threading.Thread | None = None
        self._current: tuple[float, float] | None = None
        self._walking = False

    # ------------------------------------------------------------------ public

    def start(self, points: Sequence[tuple[float, float]], speed_mps: float) -> None:
        """Cancel any active walk and start a new one. Returns immediately."""
        if len(points) < 2:
            raise ValueError("walk requires at least 2 points")
        if not (0 < speed_mps <= 10):
            raise ValueError("speed_mps must be in (0, 10]")

        # Snapshot inputs before we touch the lock — points may be a transient list.
        pts: list[tuple[float, float]] = [(float(p[0]), float(p[1])) for p in points]

        total_m = sum(haversine_m(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
        log.info(
            "walker start: %d points, %.0fm @ %.2f m/s (~%.0fs)",
            len(pts), total_m, speed_mps, total_m / speed_mps,
        )

        with self._lock:
            self._cancel_locked()
            self._cancel = threading.Event()
            self._walking = True
            self._thread = threading.Thread(
                target=self._run,
                args=(pts, float(speed_mps), self._cancel),
                name="gpsmock-walker",
                daemon=True,
            )
            self._thread.start()

    def cancel(self) -> None:
        """Stop the active walker. Safe to call when idle."""
        with self._lock:
            was_walking = self._walking
            self._cancel_locked()
        if was_walking:
            log.info("walker cancelled")

    def state(self) -> tuple[tuple[float, float] | None, bool]:
        """Return (last pushed coordinate or None, walking flag)."""
        with self._lock:
            return self._current, self._walking

    def set_current_static(self, point: tuple[float, float] | None) -> None:
        """Record a coord pushed outside of a walk (e.g., a /teleport).

        Walking flag is forced to False — this is for non-walk pushes only.
        """
        with self._lock:
            self._cancel_locked()
            self._current = point

    # ------------------------------------------------------------------ internals

    def _cancel_locked(self) -> None:
        """Lock-held cancel. Joins the worker so callers see a fully-stopped state."""
        self._cancel.set()
        thread = self._thread
        self._thread = None
        self._walking = False
        if thread is not None and thread.is_alive():
            # Release the lock while joining to avoid deadlock with the worker
            # trying to update _current at the very end.
            self._lock.release()
            try:
                thread.join(timeout=2.0)
            finally:
                self._lock.acquire()

    def _run(
        self,
        points: list[tuple[float, float]],
        base_speed: float,
        cancel: threading.Event,
    ) -> None:
        """Worker body. Walk segment-by-segment, ~1 Hz updates."""
        t0 = time.monotonic()
        completed = False
        try:
            self._publish(points[0])
            for i in range(len(points) - 1):
                if cancel.is_set():
                    return
                segment_speed = base_speed * self._rng.uniform(*SPEED_JITTER_RANGE)
                self._walk_segment(points[i], points[i + 1], segment_speed, cancel)
                if cancel.is_set():
                    return
            # Land cleanly on the final point with no jitter so the user's chosen
            # destination is exactly where the iPhone ends up.
            self._publish(points[-1], jitter=False)
            completed = True
        finally:
            with self._lock:
                self._walking = False
            if completed:
                log.info("walker finished (%.1fs)", time.monotonic() - t0)

    def _walk_segment(
        self,
        a: tuple[float, float],
        b: tuple[float, float],
        speed_mps: float,
        cancel: threading.Event,
    ) -> None:
        distance = haversine_m(a, b)
        if distance < 0.5:
            # Degenerate segment — skip without sleeping.
            return
        duration = distance / speed_mps
        ticks = max(1, int(round(duration / TICK_SECONDS)))
        for k in range(1, ticks + 1):
            if cancel.is_set():
                return
            t = k / ticks
            interp = interpolate(a, b, t)
            self._publish(interp)
            self._sleep(TICK_SECONDS)

    def _publish(self, point: tuple[float, float], *, jitter: bool = True) -> None:
        if jitter:
            point = jitter_coord(point, self._rng)
        try:
            self._push(point[0], point[1])
            log.debug("walker tick lat=%.6f lon=%.6f", point[0], point[1])
        except Exception:
            log.exception("walker push failed (will retry next tick)")
            # Don't crash the walker — let the next tick try again. Device-side
            # reconnect logic in DeviceManager handles transient USB hiccups.
        with self._lock:
            self._current = point
