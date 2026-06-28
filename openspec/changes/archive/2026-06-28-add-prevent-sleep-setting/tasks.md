## 1. SleepAssertion helper

- [x] 1.1 Add `app/Sources/Models/SleepAssertion.swift` wrapping `IOPMAssertionCreateWithName` / `IOPMAssertionRelease`, with idempotent `enable()` / `disable()` and `deinit` cleanup
- [x] 1.2 Use `kIOPMAssertPreventUserIdleSystemSleep` and a recognizable assertion name (e.g., `"GPSMock: simulated walk active"`) so it shows up cleanly under `pmset -g assertions`
- [x] 1.3 Verify `app/project.yml` already pulls IOKit (system framework auto-linked); add an explicit `import IOKit.pwr_mgt` and a project link entry only if the build fails without it

## 2. Persisted state

- [x] 2.1 Add optional `preventSleep: Bool?` to `StateStore.Snapshot` in `app/Sources/Models/StateStore.swift`
- [x] 2.2 Confirm decoding old `state.json` files (without the field) loads `preventSleep` as nil and is treated as off

## 3. AppViewModel wiring

- [x] 3.1 Add `preventSleep: Bool` (Observable) to `AppViewModel`, initialized from the loaded snapshot (default false)
- [x] 3.2 Hold a `private let sleepAssertion = SleepAssertion()` and call `enable()` / `disable()` from `setPreventSleep(_:)` plus on init when restoring `true`
- [x] 3.3 Update `persist()` to include `preventSleep` in the snapshot
- [x] 3.4 In `handleAppExit()`, call `sleepAssertion.disable()` to release before the process tears down

## 4. UI

- [x] 4.1 In `app/Sources/Views/ControlsPanel.swift`, add a `Menu` (gear icon) on the top row near the Clear button containing a `Toggle("Prevent computer from sleeping while GPSMock is open", isOn: $app.preventSleep)`
- [x] 4.2 Bind the toggle through `AppViewModel.setPreventSleep(_:)` so flipping it acquires/releases the assertion immediately

## 5. Manual verification

- [x] 5.1 Launch app, enable toggle, run `pmset -g assertions | grep GPSMock` and confirm the assertion is held
- [x] 5.2 Disable toggle, re-run `pmset -g assertions`, confirm the assertion is gone — needs UI flip; not exercised by state.json manipulation
- [x] 5.3 Quit the app while the toggle is on, confirm the assertion is released (no leak in `pmset -g assertions`)
- [x] 5.4 Set `Settings → Lock Screen → Turn display off when inactive` to 1 minute, start a long walk with the toggle on, leave the Mac idle for 5 minutes, confirm the simulated walk is still progressing when the screen wakes
- [x] 5.5 Toggle on, quit, relaunch — confirm the toggle is still on and the assertion is re-acquired

## 6. Docs

- [x] 6.1 Add a one-liner to `README.md` (or `docs/setup.md`) under "Known quirks": "When the prevent-sleep toggle is on, GPSMock holds a system-sleep assertion until you quit the app."
