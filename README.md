# GPSMock

Personal macOS tool for setting an iOS 17+ iPhone's system-level location to a point picked on a map. USB-tethered, single user, no jailbreak. Built on top of [`pymobiledevice3`](https://github.com/doronz88/pymobiledevice3) tunneld.

> ### ⚠️ Disclaimer — read before use
>
> GPSMock is a developer / hobbyist tool. By using it, you accept the following:
>
> - **Devices you own only.** Do not run this against an iPhone you don't own or aren't authorized to use.
> - **Lawful purposes only.** GPSMock must **not** be used for: fraud (insurance, refunds, fake alibis); circumventing court-ordered, parole, or employer-mandated location monitoring; stalking, harassment, or surveillance of any person; or any activity that's illegal in your jurisdiction. That includes — but isn't limited to — Taiwan's 跟蹤騷擾防制法, fraud statutes, and any equivalent in your country.
> - **You will likely break apps' Terms of Service.** Ride-sharing, dating, location-based games, banking, attendance, and similar apps explicitly forbid spoofed location. Account bans, civil claims, or refused service are on you.
> - **No warranty.** GPSMock can fail, hang, or leave your iPhone reporting a stale fix until reboot. Don't rely on it for anything that matters. The MIT license disclaims all warranty and liability — see [`LICENSE`](LICENSE).
>
> The author distributes this code as-is, for legitimate development and personal use. You are solely responsible for how you use it.

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
