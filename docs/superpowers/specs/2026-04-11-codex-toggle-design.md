# Codex Session Detection Toggle

**Date:** 2026-04-11
**Branch:** `codex-fix`
**Status:** Approved

## Problem

Code Island currently has Codex support code that runs unconditionally or is dead code. The app should be Claude Code-only by default. Users who also use Codex should be able to opt in via a settings toggle, which installs hooks and enables all Codex-related features.

## Design

### Core: `CodexFeatureGate`

A new `@MainActor ObservableObject` singleton at `ClaudeIsland/Core/CodexFeatureGate.swift` (~30-40 lines).

- Owns a `UserDefaults` key `"codexEnabled"`, default `false`.
- Exposes `@Published var isEnabled: Bool`.
- On set to `true`: calls `CodexHookInstaller.installIfNeeded()`, starts `CodexUsageMonitor`.
- On set to `false`: calls `CodexHookInstaller.uninstall()`, stops `CodexUsageMonitor` (sets snapshot to nil, cancels timer).
- `func onLaunch()`: called from `AppDelegate`; only installs Codex hooks and starts monitoring if `isEnabled == true`.

### AppDelegate

After `HookInstaller.installIfNeeded()` (line 27), add `CodexFeatureGate.shared.onLaunch()`. Claude hooks always install; Codex hooks are gated.

### Settings UI — General Tab

Add a third `TabToggle` to the existing `LazyVGrid` in `GeneralTab` (in `SystemSettingsView.swift`):

- Icon: a Codex-appropriate SF Symbol (e.g. `terminal.fill` or `app.connected.to.app.below.fill`)
- Label: "Codex Support"
- Observes `CodexFeatureGate.shared.isEnabled`
- Tapping flips the property; side-effects fire automatically

### UI Gating

**`ClaudeInstancesView`**: The `CodexUsageStatsBar` (2 locations — notch overlay and expanded list) is wrapped in `if codexGate.isEnabled`. When off, the bar doesn't render.

**`CodexUsageMonitor`**: The periodic refresh timer and initial refresh only fire when the gate is enabled. When toggled off, timer stops and `snapshot` is set to `nil`.

### Session Behavior

Existing Codex sessions in `SessionStore` are **not** cleared when the toggle is turned off. They expire naturally. With hooks uninstalled and monitoring stopped, no new Codex events arrive.

`SessionStore` itself is not gated — it processes whatever events arrive on the socket. The gate controls whether events are generated in the first place.

## Dead Code Removal

The entire `CodexSessionTracking.swift` (873 lines) is dead code on the `codex-fix` branch. Every type defined in it (`CodexSessionStore`, `CodexRolloutDiscovery`, `CodexRolloutWatcher`, `CodexRolloutReducer`, `CodexRolloutSnapshot`, `CodexRolloutEvent`, `CodexRolloutWatchTarget`, `CodexTrackedSessionRecord`, `CodexSessionPhase`, `CodexSessionOrigin`, `CodexSessionAttachmentState`, `CodexJumpTarget`, `CodexSessionMetadata`) is only referenced within the file itself.

The sole external reference is `CodexUsage.swift:68` using `CodexRolloutDiscovery.defaultRootURL` for the path `~/.codex/sessions` — this is inlined.

**Files that stay:**
- `CodexHookInstaller.swift` — called by `CodexFeatureGate`
- `CodexChatHistoryParser.swift` — called by `SessionStore` for Codex chat history
- `CodexUsage.swift` — `CodexUsageMonitor` / `CodexUsageStatsBar`, gated by toggle
- `HookHealthCheck.swift` — diagnostic references to `CodexHookInstallerManifest`

## File Changes

| File | Change |
|------|--------|
| `ClaudeIsland/Core/CodexFeatureGate.swift` | **New** — singleton gate (~30-40 lines) |
| `ClaudeIsland/App/AppDelegate.swift` | Add `CodexFeatureGate.shared.onLaunch()` |
| `ClaudeIsland/UI/Views/SystemSettingsView.swift` | `GeneralTab`: add Codex Support toggle |
| `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` | Gate `CodexUsageStatsBar` on `isEnabled` (2 spots) |
| `ClaudeIsland/Services/Session/CodexUsage.swift` | Inline `defaultRootURL`; gate monitor on feature flag |
| `ClaudeIsland/Services/Session/CodexSessionTracking.swift` | **Delete** (873 lines, all dead) |
