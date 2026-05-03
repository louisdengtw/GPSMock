# Setup

One-time setup, then the three-terminal launch flow. macOS 14+ Apple Silicon, iPhone iOS 17 / 18 / 26.

## 1. iPhone

1. **Enable Developer Mode**: Settings → Privacy & Security → Developer Mode → On. Reboot when prompted.
2. **Trust this Mac**: plug iPhone into Mac via USB, tap *Trust* on the iPhone.
3. (iOS 17+ only, one-time) Allow personalized Developer Disk Image mounting: Settings → Privacy & Security → Developer Mode keeps an internal flag; the mounter step in §3 below handles the rest.

## 2. Mac — Python and pymobiledevice3

```bash
# from repo root
make sidecar-install
```

This creates `sidecar/.venv` and installs `pymobiledevice3`, `fastapi`, `uvicorn`. Editable so you can iterate.

If you prefer manually:

```bash
cd sidecar
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
```

## 3. Mac — Xcode project

The Xcode project is generated from `app/project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
make app-generate   # writes app/GPSMock.xcodeproj
make app            # opens the project in Xcode; press ⌘R to run
```

`GPSMock.xcodeproj` is git-ignored — regenerate any time.

## 4. Launch flow (three terminals)

Order matters. Each step must succeed before the next.

```bash
# Terminal A — tunneld (root; long-lived; leave open)
sudo pymobiledevice3 remote tunneld

# Terminal B — sidecar
make sidecar

# Terminal C (or Xcode) — app
make app
```

The app's status pill walks you through any missing piece. The first run on each iOS version may pause for 10–60 s while `pymobiledevice3` mounts the personalized Developer Disk Image — this is expected.

## 5. Troubleshooting matrix

The status pill shows one of three states. Each maps to a single concrete fix.

| Pill says | Means | Fix |
|---|---|---|
| `Sidecar not running` | App can't reach `127.0.0.1:5555` | Run `make sidecar` (Terminal B). If it errors `address already in use`, check `lsof -i :5555` for a stale process and kill it. |
| `Tunneld unreachable` | Sidecar reached, tunneld isn't | Run `sudo pymobiledevice3 remote tunneld` (Terminal A). Re-prompt for password if your sudo session expired. **Also: if Xcode's "Devices and Simulators" window is open, it holds the RemoteXPC tunnel exclusively and tunneld can't connect — close that window (Xcode itself can stay open).** |
| `No iPhone detected` | Tunneld is up but sees no device | Plug the iPhone in via USB. If freshly trusted, unplug/replug. Confirm Developer Mode is on. |
| `Connected: <name>` | Ready | Tap the map. |

Other things to try when you're really stuck:

- **Mounter errors** (visible in sidecar console): delete `~/Library/Developer/Xcode/iOS DeviceSupport/<version>/` and re-run; the mounter will re-fetch the personalized image.
- **iOS 26 DDI mount hangs / times out**: pymobiledevice3's `auto_mount_personalized` is unreliable on iOS 26. Easiest fix: open Xcode → Window → Devices and Simulators (⌘⇧2), wait until your iPhone shows in "Connected" with full info (model / iOS / identifier) on the right pane — Xcode mounts the personalized DDI itself in this step. Then **close that window** (so it releases the tunnel), restart `tunneld.sh`, and re-run. The sidecar detects the existing mount via `is_image_mounted` and skips the flaky path. The mount persists on the iPhone until reboot.
- **iPhone stuck on a fake fix after a hard kill**: wait ~60 s for iOS's own simulation timeout, or reboot the iPhone if you're impatient.
- **Cable**: a USB-C-to-Lightning data cable (not charge-only) is required.

## 6. Updating pymobiledevice3

`pymobiledevice3` evolves fast. The pinned version in `sidecar/pyproject.toml` is what's been verified locally. To upgrade:

```bash
cd sidecar
source .venv/bin/activate
pip install --upgrade pymobiledevice3
make smoke   # re-run the smoke flow against the iPhone
```

If the upgrade breaks `sidecar/device.py` because the underlying API moved, the sidecar's exception path will surface the original error verbatim — fix the wrapper, don't pin around it forever.
