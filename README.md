# GPSMock

Personal macOS tool for setting an iOS 17+ iPhone's system-level location to a point picked on a map. USB-tethered, single user, no jailbreak. Built on top of [`pymobiledevice3`](https://github.com/doronz88/pymobiledevice3) tunneld.

> **Disclaimer.** Use only on devices you own. Spoofing your device's location can break or violate the terms of service of apps that rely on location (ride-sharing, dating, games, banking, etc.) — that's on you. No warranty; see [`LICENSE`](LICENSE).

```
GPSMock.app (SwiftUI, MapKit, OSRM)
        │ HTTP (127.0.0.1:5555)
        ▼
sidecar/main.py (FastAPI + pymobiledevice3 wrapper)
        │
        ▼
sudo pymobiledevice3 remote tunneld
        │ RemoteXPC over USB
        ▼
   [iPhone]
```

## Quick start

Three terminals; order matters.

```bash
# Terminal A — tunneld (root, long-lived)
sudo pymobiledevice3 remote tunneld

# Terminal B — sidecar
make sidecar

# Then open the macOS app
make app
```

See [`docs/setup.md`](docs/setup.md) for one-time setup (Developer Mode, Mac trust, Python env) and the troubleshooting matrix.

## Layout

```
gpsmock/
├── README.md
├── Makefile
├── app/                  Xcode SwiftUI project (generated via xcodegen)
├── sidecar/              FastAPI + pymobiledevice3 wrapper
├── docs/setup.md         Setup + troubleshooting
└── openspec/             Specs and change history
```

## Status

v1 in progress. See `openspec/changes/add-gpsmock/tasks.md` for current state.

## Known quirks

- When the **Prevent computer from sleeping while GPSMock is open** toggle (gear menu in the controls panel) is on, GPSMock holds an `IOPMAssertPreventUserIdleSystemSleep` assertion until you quit the app. The display is still allowed to sleep.
