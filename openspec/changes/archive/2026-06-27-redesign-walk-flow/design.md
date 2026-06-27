## Context

Walk mode in GPSMock today uses a centered overlay sheet (`WalkPreviewSheet`) that appears once OSRM (or the straight-line fallback) returns a polyline. The sheet sits in the middle of the window, on top of the map, and physically covers the route the user is supposed to be confirming. The start point of the route is determined by `AppViewModel.currentOrigin()` with the priority `customOrigin > iPhone simulated GPS > Mac CoreLocation > map center`. The user can technically override the start by dragging an unlabeled green dot on the map, but: (a) the green dot is not visible while the sheet is up because the sheet covers it, (b) the dot has no label or affordance hinting that it's draggable, and (c) there's no way to clear a custom origin once set short of canceling and re-tapping the destination.

The walk feature works mechanically but the planning UX is the main usability complaint. This redesign is local to the SwiftUI views and `AppViewModel` — no sidecar / OSRM / persistence changes — so the blast radius is small and the change can ship independently.

## Goals / Non-Goals

**Goals:**
- The route polyline SHALL never be occluded by the preview/confirm UI in default window sizes (≥ 1000×700).
- A user who taps Walk → destination SHALL be able to change the start point without canceling the preview.
- The "you can change the start" affordance SHALL be discoverable on first use (label + one-time hint), not require docs.
- "Reset to default origin" SHALL be a single click, not a re-tap of destination.
- Re-planning after a start-point change SHALL keep the preview panel open and show progress inline.

**Non-Goals:**
- Changing OSRM behavior, fallback geometry, or `/walk` payload shape. Route-planning capability is unchanged.
- Editing the destination from the preview. Tapping the map already replaces the destination — no new affordance needed.
- Multi-waypoint routes. Still origin → destination only.
- Preview while walking. Mid-walk reroute is out of scope; user still cancels and re-plans.
- Teleport mode. No UI changes there.

## Decisions

### Move the preview from `.center` overlay to a `.bottom` docked panel

`ContentView.swift` currently does:
```swift
.overlay(alignment: .center) {
    if let plan = app.pendingRoute, app.mode == .walk {
        WalkPreviewSheet(plan: plan)
    }
}
```
We change `alignment` to `.bottom` and stack above `ControlsPanel` (or, more precisely, reorder so the preview sits between the map and the controls panel from the user's visual perspective). The panel's max width stays around `360–480 pt` and it grows horizontally with the window, but its vertical footprint stays compact (one row of stats + one row of buttons).

**Alternatives considered:**
- *Sidebar (`.trailing`)*: Wastes horizontal space when the route is mostly vertical; on a tall map a sidebar would itself occlude the route.
- *Floating, draggable*: Adds drag UI complexity for marginal benefit; default position is enough.
- *Inline in `ControlsPanel`*: Mixes "active walk being planned" with persistent controls; bad mental model when the user wants to cancel out.

### Add an explicit `isPickingStart` interaction state to `AppViewModel`

While in walk mode and previewing a route, the user can press "Set start here" in the preview to enter a transient `isPickingStart = true` state. The next map tap goes to `setCustomOrigin(coord)` (and re-plans) instead of `mapTapped(coord)` setting the destination. The state self-clears on success, on Esc, or on a second click of the toggle button.

Why a mode flag instead of e.g. a separate "drag the green dot" affordance only:
- Drag-to-edit alone is hidden; users have to find a small dot first. The button gives a discoverable entry point.
- It also handles the case where the start is far off-screen (the user pans there and taps).
- It keeps `mapTapped` simple — one branch per state.

### Keep `customOrigin` semantics, add `resetCustomOrigin()`

Today, `customOrigin` is set by `setCustomOrigin(_:)` (called from the green-dot drag) and only ever cleared by `cancelPreview()` / `clearAll()`. We add `resetCustomOrigin()` which sets `customOrigin = nil` and re-plans, called from a "Reset start to GPS" button in the preview. The fallback chain (`statusRef.current → userLocation → lastKnownRegion.center`) is unchanged.

The preview SHALL only show the "Reset start to GPS" button when `customOrigin != nil`, otherwise the action is meaningless.

### Show start handle as a labeled "Start" annotation with one-time hint

The existing green-dot annotation in `MapSurface.swift` becomes:
- Always labeled "Start" (annotation title) when a route is shown.
- On the first time `pendingRoute` is set in walk mode in this user's lifetime, show a callout/tooltip near the dot saying "Drag to change start". Persist a `seenStartHint: Bool` in `state.json` so the hint shows exactly once across launches.
- Drag gesture on the dot is unchanged — it already calls `setCustomOrigin`.

**Alternatives considered:**
- *Always-visible hint label*: Too noisy after the first encounter.
- *No hint, only the button*: Loses the existing drag affordance for power users.

### Re-plan in place; do not blank the preview

When `setCustomOrigin` or `resetCustomOrigin` triggers a new `planRoute(...)`, `isPlanningRoute` flips to true. Today this just hides the polyline; the preview panel can also unmount because `pendingRoute` is set to `nil` at the start of `planRoute` (`self.pendingRoute = nil`). We change `planRoute` to *not* nil out `pendingRoute` while a previous plan exists — instead, the existing polyline stays rendered (slightly faded) and the preview panel shows an inline spinner with "Re-planning…". When the new plan returns, both update atomically.

### One-time hint persistence: piggyback on `state.json`

`StateStore.Snapshot` already carries optional fields (`preventSleep`). Add another optional `seenStartHint: Bool?` (default nil → unseen). No migration risk: missing field decodes to nil, treated as unseen, hint shows once.

## Risks / Trade-offs

- [Risk] Re-planning while keeping the old polyline rendered may briefly show a stale route shape if the user changed the start to somewhere very far away. → Mitigation: fade the polyline to ~40% opacity while `isPlanningRoute && pendingRoute != nil` so it reads as "stale, refreshing".
- [Risk] Bottom-docked preview reduces the visible map area near the user's controls. → Mitigation: the panel is short (one stat row + one button row), and only appears in walk mode after a destination is picked. The default idle map area is unchanged.
- [Risk] `isPickingStart` adds a hidden mode the user could get stuck in. → Mitigation: the button toggles (text becomes "Cancel pick"), Esc exits, picking a start auto-exits, and changing modes clears it.
- [Risk] One-time hint is annoying if the user wipes `state.json` for unrelated reasons. → Mitigation: acceptable; the hint is short and only fires once per `state.json` lifetime. Not worth a separate prefs file.
- [Trade-off] We are not redesigning teleport mode. Teleport users won't get the same "preview before commit" treatment. This keeps scope tight; if teleport ever grows complexity, revisit.
