## 1. State plumbing

- [x] 1.1 Add optional `seenStartHint: Bool?` to `StateStore.Snapshot` in `app/Sources/Models/StateStore.swift`; verify decoding old files without the field returns nil
- [x] 1.2 Add `var isPickingStart: Bool = false` and `var seenStartHint: Bool` (loaded from snapshot, default false) to `AppViewModel`
- [x] 1.3 Update `AppViewModel.persist()` to include `seenStartHint` in the written snapshot

## 2. AppViewModel actions

- [x] 2.1 Add `func beginPickingStart()` and `func endPickingStart()` that toggle `isPickingStart`
- [x] 2.2 Modify `mapTapped(at:)` so that when `isPickingStart && mode == .walk` the tap calls `setCustomOrigin(coord)` and exits picking, instead of replacing the destination
- [x] 2.3 Add `func resetCustomOrigin()` that clears `customOrigin` and re-plans if `pendingTarget != nil && mode == .walk`
- [x] 2.4 In `setMode(_:)`, also clear `isPickingStart` when leaving `.walk`
- [x] 2.5 Modify `planRoute(to:)` to NOT set `pendingRoute = nil` when a previous plan exists; keep the old plan visible while `isPlanningRoute = true`, replace atomically when the new plan arrives
- [x] 2.6 Add a one-shot helper that flips `seenStartHint` to true and persists, called the first time the preview panel renders

## 3. Map surface

- [x] 3.1 In `MapSurface.swift`, change the start annotation's title from "Start" placeholder to a proper labeled annotation; keep the existing drag gesture wiring to `setCustomOrigin`
- [x] 3.2 Add a one-time tooltip/callout near the start handle when `app.seenStartHint == false && app.pendingRoute != nil`, with text "Drag to change start"; tooltip dismisses on first interaction or after `~6 s`
- [x] 3.3 While `app.isPlanningRoute && app.pendingRoute != nil`, render the existing polyline at `opacity(0.4)` to read as "stale, refreshing"
- [x] 3.4 Ensure the tap gesture path respects `isPickingStart` (route tap to the new branch in `mapTapped`)

## 4. Preview panel redesign

- [x] 4.1 In `WalkPreviewSheet.swift`, restructure the layout into a horizontal row: distance · ETA · fallback chip on the left, action buttons on the right
- [x] 4.2 Add a "Set start here" button that toggles `app.beginPickingStart()` / `app.endPickingStart()`; show its pressed/active state when `app.isPickingStart == true`
- [x] 4.3 Add a "Reset start to GPS" button visible only when `app.customOrigin != nil`, calling `app.resetCustomOrigin()`
- [x] 4.4 Show an inline `ProgressView` + "Re-planning…" label while `app.isPlanningRoute && app.pendingRoute != nil`; disable Confirm in that state
- [x] 4.5 Constrain panel max width (~480 pt) and keep height to roughly two compact rows so it fits above `ControlsPanel` without dominating the screen

## 5. Layout integration

- [x] 5.1 In `ContentView.swift`, change the `WalkPreviewSheet` overlay alignment from `.center` to `.bottom`, with bottom padding sized to clear `ControlsPanel`
- [x] 5.2 Verify on a 1000×700 window that the polyline's bounding box at default zoom is fully visible above the docked preview
- [x] 5.3 Verify on a tall narrow window (e.g., 800×1100) that the preview still docks cleanly and does not bleed off the controls panel

## 6. Esc key wiring

- [x] 6.1 Add a keyboard shortcut (Esc) at the `ContentView` level that, when `app.isPickingStart == true`, calls `app.endPickingStart()`; otherwise no-op so it doesn't steal Esc from other surfaces

## 7. Manual test plan

- [x] 7.1 Walk → tap destination → confirm the polyline is fully visible and the preview is docked at the bottom
- [x] 7.2 Drag the green Start handle to a new map location → verify route re-plans and old polyline fades during re-plan
- [x] 7.3 Click "Set start here" → tap a map point → verify origin updates, picking state exits, button reverts
- [x] 7.4 Click "Set start here" → press Esc → verify picking state exits, no origin change
- [x] 7.5 With a custom origin set, click "Reset start to GPS" → verify route re-plans from default origin and the button hides
- [x] 7.6 Quit and relaunch → verify the start-handle hint does NOT reappear (`seenStartHint` persisted)
- [x] 7.7 Delete `~/Library/Application Support/GPSMock/state.json`, relaunch → verify hint reappears once on the first walk preview
- [x] 7.8 Switch from Walk to Teleport mode while in `pickingStart` → verify state clears and the next tap behaves as a teleport target
