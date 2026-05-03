"""Walker pacing and jitter tests, run against a fake clock."""

from __future__ import annotations

import math
import random
import threading

import pytest

from gpsmock_sidecar.walker import (
    MAX_COORD_JITTER_M,
    SPEED_JITTER_RANGE,
    Walker,
    haversine_m,
    interpolate,
    jitter_coord,
)


# ----------------------------------------------------------- pure-math sanity


def test_haversine_zero():
    assert haversine_m((25.0, 121.0), (25.0, 121.0)) == 0.0


def test_haversine_one_degree_lat():
    # 1° latitude ≈ 111 km
    d = haversine_m((25.0, 121.0), (26.0, 121.0))
    assert 110_000 < d < 112_000


def test_interpolate_endpoints():
    a, b = (0.0, 0.0), (10.0, 20.0)
    assert interpolate(a, b, 0) == a
    assert interpolate(a, b, 1) == b
    mid = interpolate(a, b, 0.5)
    assert mid == (5.0, 10.0)


# ----------------------------------------------------------- jitter bounds


def test_jitter_within_1m():
    rng = random.Random(42)
    point = (25.0330, 121.5654)
    for _ in range(2000):
        jittered = jitter_coord(point, rng)
        d = haversine_m(point, jittered)
        assert d <= MAX_COORD_JITTER_M + 1e-3, f"jitter {d:.4f} m exceeded cap"


def test_speed_multiplier_in_range():
    rng = random.Random(7)
    samples = [rng.uniform(*SPEED_JITTER_RANGE) for _ in range(1000)]
    assert min(samples) >= SPEED_JITTER_RANGE[0]
    assert max(samples) <= SPEED_JITTER_RANGE[1]


# ----------------------------------------------------------- walker pacing


class FakeClock:
    """Deterministic substitute for time.sleep — accumulates simulated time."""

    def __init__(self):
        self.now = 0.0

    def sleep(self, seconds: float) -> None:
        self.now += seconds


def _capture_walker(speed: float, polyline, *, seed: int = 0) -> tuple[list, FakeClock]:
    """Run a walker synchronously by replacing the worker thread with a direct call."""
    pushed: list[tuple[float, float]] = []
    clock = FakeClock()
    rng = random.Random(seed)

    def push(lat: float, lon: float) -> None:
        pushed.append((lat, lon))

    w = Walker(push=push, sleeper=clock.sleep, rng=rng)

    # Drive the worker body directly to avoid thread timing in tests.
    cancel = threading.Event()
    w._cancel = cancel
    w._walking = True
    pts = [tuple(p) for p in polyline]
    w._run(pts, speed, cancel)
    return pushed, clock


def test_pacing_30s_walk_at_1_3_mps():
    """30 s synthetic walk along a 39 m straight segment should produce ~30 ticks."""
    speed = 1.3  # m/s
    distance = 39.0  # m → ~30 s
    # Build a segment of approximately `distance` meters in latitude.
    deg_lat = distance / 111_320.0
    polyline = [(25.0, 121.0), (25.0 + deg_lat, 121.0)]
    pushed, clock = _capture_walker(speed, polyline)

    # First publish is the starting point; subsequent publishes are 1 per tick.
    # Wall-clock duration in fake time should be roughly distance/speed.
    expected_duration = distance / speed
    assert abs(clock.now - expected_duration) <= expected_duration * 0.20

    # Per-spec: ~100 updates per 100 m at 1 m/s → at 1.3 m/s × 30 s, ~30 ticks ±15%.
    # The walker emits one start point + ticks.
    ticks = len(pushed) - 1  # subtract the leading start-point publish
    assert 0.85 * expected_duration <= ticks <= 1.15 * expected_duration + 1


def test_walk_lands_on_final_point():
    polyline = [(25.0, 121.0), (25.001, 121.001)]
    pushed, _ = _capture_walker(1.3, polyline, seed=1)
    last = pushed[-1]
    # No jitter on the final point per walker contract.
    assert last == polyline[-1]


# ----------------------------------------------------------- single-flight


def test_start_replaces_walk():
    """Starting a new walk while another is active must not leave both running."""
    pushed: list[tuple[float, float]] = []

    def push(lat: float, lon: float) -> None:
        pushed.append((lat, lon))

    w = Walker(push=push)  # real time.sleep; we'll cancel almost immediately
    long_walk = [(25.0, 121.0), (25.5, 121.5)]
    w.start(long_walk, speed_mps=1.0)
    # Replace immediately with a tiny walk.
    short_walk = [(25.0, 121.0), (25.00001, 121.00001)]
    w.start(short_walk, speed_mps=1.0)

    # Wait briefly for short walk to finish.
    import time

    deadline = time.time() + 5
    while time.time() < deadline:
        _, walking = w.state()
        if not walking:
            break
        time.sleep(0.05)

    _, walking = w.state()
    assert walking is False, "walker should have settled after the second start"


# ----------------------------------------------------------- input validation


def test_walk_requires_two_points():
    w = Walker(push=lambda *_: None)
    with pytest.raises(ValueError):
        w.start([(25.0, 121.0)], speed_mps=1.0)


def test_walk_speed_range():
    w = Walker(push=lambda *_: None)
    with pytest.raises(ValueError):
        w.start([(25.0, 121.0), (25.1, 121.1)], speed_mps=0)
    with pytest.raises(ValueError):
        w.start([(25.0, 121.0), (25.1, 121.1)], speed_mps=11)
