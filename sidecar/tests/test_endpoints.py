"""Endpoint coverage with a stubbed DeviceManager (no real iPhone needed)."""

from __future__ import annotations

import time

import pytest
from fastapi.testclient import TestClient

from gpsmock_sidecar.device import (
    DeviceInfo,
    MounterError,
    NoDeviceError,
    TunneldUnreachableError,
)
from gpsmock_sidecar.main import create_app


# ----------------------------------------------------------- stubs


class StubDevice:
    """In-memory replacement for DeviceManager."""

    def __init__(self, *, info: DeviceInfo | None = None, raise_on_info=None):
        self._info = info or DeviceInfo("ABC", "Test iPhone", "17.5")
        self._raise_on_info = raise_on_info
        self.last_set: tuple[float, float] | None = None
        self.cleared: int = 0

    def get_device_info(self) -> DeviceInfo:
        if self._raise_on_info is not None:
            raise self._raise_on_info
        return self._info

    def set_location(self, lat: float, lon: float) -> None:
        self.last_set = (lat, lon)

    def clear_location(self) -> None:
        self.cleared += 1

    def shutdown(self) -> None:
        pass


@pytest.fixture
def client_with_device():
    device = StubDevice()
    app = create_app(device=device)
    return TestClient(app), device


@pytest.fixture
def client_no_device():
    device = StubDevice(raise_on_info=NoDeviceError("no iPhone"))
    app = create_app(device=device)
    return TestClient(app), device


@pytest.fixture
def client_no_tunneld():
    device = StubDevice(raise_on_info=TunneldUnreachableError("tunneld down"))
    app = create_app(device=device)
    return TestClient(app), device


@pytest.fixture
def client_mounter_failure():
    device = StubDevice(raise_on_info=MounterError("ddi mount failed"))
    app = create_app(device=device)
    return TestClient(app), device


# ----------------------------------------------------------- /health


def test_health_ok(client_with_device):
    client, _ = client_with_device
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert "version" in body


# ----------------------------------------------------------- /device


def test_device_present(client_with_device):
    client, _ = client_with_device
    r = client.get("/device")
    assert r.status_code == 200
    body = r.json()
    assert body == {"udid": "ABC", "name": "Test iPhone", "ios_version": "17.5"}


def test_device_absent(client_no_device):
    client, _ = client_no_device
    r = client.get("/device")
    assert r.status_code == 404
    assert r.json()["error"] == "no_device"


def test_device_tunneld_down(client_no_tunneld):
    client, _ = client_no_tunneld
    r = client.get("/device")
    assert r.status_code == 503
    assert r.json()["error"] == "tunneld_unreachable"


def test_device_mounter_failure(client_mounter_failure):
    client, _ = client_mounter_failure
    r = client.get("/device")
    assert r.status_code == 503
    assert r.json()["error"] == "mounter_failed"


# ----------------------------------------------------------- /teleport


def test_teleport_ok(client_with_device):
    client, device = client_with_device
    r = client.post("/teleport", json={"lat": 25.0330, "lon": 121.5654})
    assert r.status_code == 200
    assert device.last_set == (25.0330, 121.5654)


def test_teleport_validation_missing(client_with_device):
    client, _ = client_with_device
    r = client.post("/teleport", json={"lat": 25.0})
    assert r.status_code == 422  # FastAPI validation


def test_teleport_validation_out_of_range(client_with_device):
    client, _ = client_with_device
    r = client.post("/teleport", json={"lat": 200, "lon": 0})
    assert r.status_code == 422


# ----------------------------------------------------------- /walk


def test_walk_started(client_with_device):
    client, _ = client_with_device
    body = {
        "points": [[25.0, 121.0], [25.00001, 121.00001]],
        "speed_mps": 1.3,
    }
    r = client.post("/walk", json=body)
    assert r.status_code == 202


def test_walk_too_few_points(client_with_device):
    client, _ = client_with_device
    r = client.post(
        "/walk", json={"points": [[25.0, 121.0]], "speed_mps": 1.3}
    )
    assert r.status_code in (400, 422)


def test_walk_speed_out_of_range(client_with_device):
    client, _ = client_with_device
    r = client.post(
        "/walk",
        json={"points": [[25.0, 121.0], [25.1, 121.1]], "speed_mps": 0},
    )
    assert r.status_code in (400, 422)


def test_walk_no_device(client_no_device):
    client, _ = client_no_device
    body = {"points": [[25.0, 121.0], [25.1, 121.1]], "speed_mps": 1.3}
    r = client.post("/walk", json=body)
    assert r.status_code == 503


# ----------------------------------------------------------- /clear


def test_clear_when_idle(client_with_device):
    client, device = client_with_device
    r = client.post("/clear")
    assert r.status_code == 200
    assert device.cleared >= 1


def test_clear_during_walk(client_with_device):
    """walk replaces walk: starting a walk then /clear must stop everything."""
    client, device = client_with_device
    body = {
        "points": [[25.0, 121.0], [25.5, 121.5]],
        "speed_mps": 1.0,
    }
    client.post("/walk", json=body)
    r = client.post("/clear")
    assert r.status_code == 200
    s = client.get("/status").json()
    assert s["walking"] is False
    assert s["current"] is None


# ----------------------------------------------------------- /status


def test_status_idle(client_with_device):
    client, _ = client_with_device
    r = client.get("/status")
    assert r.status_code == 200
    assert r.json() == {"current": None, "walking": False}


def test_status_after_teleport(client_with_device):
    client, _ = client_with_device
    client.post("/teleport", json={"lat": 25.0, "lon": 121.0})
    s = client.get("/status").json()
    assert s["walking"] is False
    assert s["current"] == [25.0, 121.0]


# ----------------------------------------------------------- walk-replaces-walk


def test_walk_replaces_walk(client_with_device):
    """Two POST /walk in a row → only the second walker should be active."""
    client, _ = client_with_device
    long_walk = {
        "points": [[25.0, 121.0], [25.5, 121.5]],
        "speed_mps": 1.0,
    }
    short_walk = {
        "points": [[25.0, 121.0], [25.00001, 121.00001]],
        "speed_mps": 1.0,
    }
    r1 = client.post("/walk", json=long_walk)
    r2 = client.post("/walk", json=short_walk)
    assert r1.status_code == 202
    assert r2.status_code == 202

    # The short walk completes near-instantly; wait briefly for walking → False.
    deadline = time.time() + 5
    while time.time() < deadline:
        if client.get("/status").json()["walking"] is False:
            break
        time.sleep(0.05)
    s = client.get("/status").json()
    assert s["walking"] is False
