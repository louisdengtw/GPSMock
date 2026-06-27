## Why

Walk mode is the most-used feature but its current UX has two concrete failures users hit on their first attempt: (1) the OSRM-derived start point is sometimes wrong (iPhone GPS lags, Mac CoreLocation drifts, or the user wants to simulate a walk from somewhere they aren't) and there is no obvious way to change it; and (2) the `WalkPreviewSheet` is rendered as a centered overlay that physically covers the polyline it is asking the user to confirm, so users can't see the route they're approving. The walk planning flow needs to surface the start point as an explicit, editable thing and stop occluding the route during the confirm step.

## What Changes

- **BREAKING (UI-only):** Move `WalkPreviewSheet` out of the map's center. It becomes a docked panel anchored to the bottom edge (above `ControlsPanel`), wide but short, never overlapping the polyline's bounding box.
- Promote the start point to a first-class, labeled, draggable map handle with a visible hint ("drag to change start") the first time a route is shown, instead of an unlabeled green dot the user has to discover.
- Add an explicit "Set start here" affordance in the walk preview: a button that puts the app into a transient "pick start on map" state, where the next map tap sets `customOrigin` instead of the destination. Tapping the same button again, or pressing Esc, exits the state.
- Add a "Reset start to GPS" action in the walk preview that clears `customOrigin`, falling back to the existing `currentOrigin` priority (iPhone GPS → Mac CoreLocation → map center).
- When the route is being re-planned after a start-point change, show an inline spinner inside the preview panel rather than blanking the polyline.
- Keep all existing keyboard / non-walk-mode behavior unchanged. Teleport mode is untouched.

## Capabilities

### New Capabilities
<!-- None — this is a UX rework of existing capabilities. -->

### Modified Capabilities
- `map-ui`: the "Walk preview and confirmation" requirement is rewritten to specify (a) the preview's docked, non-occluding placement, (b) an explicit start-point handle with affordance hint, (c) explicit "Set start here" and "Reset start to GPS" actions, and (d) re-planning UI behavior when the start changes.

## Impact

- **App code**:
  - `app/Sources/ContentView.swift`: change `WalkPreviewSheet` overlay alignment from `.center` to `.bottom` (above controls), constrain height.
  - `app/Sources/Views/WalkPreviewSheet.swift`: redesigned layout with horizontal stat row, inline re-plan spinner, and two new buttons (`Set start here`, `Reset start to GPS`).
  - `app/Sources/Views/MapSurface.swift`: start handle gets a label ("Start"), a callout/tooltip hint on first appearance, and respects a new `pickingStart` state so map taps can set the origin instead of the destination.
  - `app/Sources/Models/AppViewModel.swift`: add `isPickingStart: Bool` interaction state, a `beginPickingStart()` / `endPickingStart()` pair, and a `resetCustomOrigin()` that clears `customOrigin` and re-plans.
- **Persisted state**: none. The "first-time hint" flag may be persisted in `state.json` (additive) so the hint is shown once per user, not every relaunch.
- **Sidecar / iPhone**: no impact. All changes are local to the macOS app's UI layer; `/walk`, `/teleport`, and OSRM behavior are unchanged.
- **Tests**: no automated UI tests in repo today; manual test plan updated in `tasks.md`.
