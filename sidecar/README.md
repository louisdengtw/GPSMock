# gpsmock-sidecar

FastAPI process that wraps `pymobiledevice3` and exposes 6 endpoints to the SwiftUI app on `127.0.0.1:5555`.

## Run

```bash
# from repo root
make sidecar-install   # one-time
make sidecar           # serves on 127.0.0.1:5555
```

`pymobiledevice3 remote tunneld` must already be running as root in another terminal.

## Endpoints

```bash
# Liveness
curl -s http://127.0.0.1:5555/health
# {"ok": true, "version": "0.1.0"}

# Connected iPhone (404 if none, 503 if tunneld is down)
curl -s http://127.0.0.1:5555/device
# {"udid": "...", "name": "Louis's iPhone", "ios_version": "17.5"}

# Teleport
curl -s -X POST http://127.0.0.1:5555/teleport \
  -H 'content-type: application/json' \
  -d '{"lat": 25.0330, "lon": 121.5654}'
# {"ok": true}

# Walk a polyline at 1.3 m/s
curl -s -X POST http://127.0.0.1:5555/walk \
  -H 'content-type: application/json' \
  -d '{"points": [[25.0330, 121.5654], [25.0340, 121.5664]], "speed_mps": 1.3}'
# {"ok": true}

# Status (poll at 1 Hz from the app)
curl -s http://127.0.0.1:5555/status
# {"current": [25.0335, 121.5659], "walking": true}

# Clear and return to real GPS
curl -s -X POST http://127.0.0.1:5555/clear
# {"ok": true}
```

## Tests

```bash
make sidecar-test
```

Tests stub `DeviceManager` so they run without a device. Hardware-side checks live in `openspec/changes/add-gpsmock/tasks.md` §14.

## Layout

```
sidecar/
├── pyproject.toml
├── README.md
├── gpsmock_sidecar/
│   ├── __init__.py
│   ├── __main__.py    `python -m gpsmock_sidecar`
│   ├── main.py        FastAPI app + entrypoint
│   ├── device.py      pymobiledevice3 wrapper
│   └── walker.py      polyline interpolator
└── tests/
    ├── test_walker.py
    └── test_endpoints.py
```
