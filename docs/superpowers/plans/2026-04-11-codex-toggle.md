# Codex Session Detection Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex support opt-in via a settings toggle — off by default, enabling hooks + usage monitoring + UI when turned on.

**Architecture:** A new `CodexFeatureGate` singleton owns the `UserDefaults` key and triggers install/uninstall side-effects. UI views and the usage monitor observe the gate. Dead code from the prior Codex session tracking system is removed.

**Tech Stack:** Swift, SwiftUI, UserDefaults, Combine

**Note:** No local Xcode build — verification is via push to `main` and GitHub Actions CI.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `ClaudeIsland/Services/Session/CodexSessionTracking.swift` | **Delete** | Dead code (873 lines) |
| `ClaudeIsland/Services/Session/CodexUsage.swift` | **Modify** | Inline `defaultRootURL`, gate monitor |
| `ClaudeIsland/Core/Localization.swift` | **Modify** | Add `codexSupport` L10n entry |
| `ClaudeIsland/Core/CodexFeatureGate.swift` | **Create** | Singleton gate for all Codex features |
| `ClaudeIsland/App/AppDelegate.swift` | **Modify** | Wire gate on launch |
| `ClaudeIsland/UI/Views/SystemSettingsView.swift` | **Modify** | Add toggle to General tab |
| `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` | **Modify** | Gate Codex usage bar |

---

### Task 1: Delete dead code — `CodexSessionTracking.swift`

**Files:**
- Delete: `ClaudeIsland/Services/Session/CodexSessionTracking.swift`

- [ ] **Step 1: Delete the file**

```bash
rm ClaudeIsland/Services/Session/CodexSessionTracking.swift
```

- [ ] **Step 2: Commit**

```bash
git add -u ClaudeIsland/Services/Session/CodexSessionTracking.swift
git commit -m "chore: remove dead CodexSessionTracking (873 lines, no external callers)"
```

---

### Task 2: Inline `defaultRootURL` in `CodexUsage.swift`

**Files:**
- Modify: `ClaudeIsland/Services/Session/CodexUsage.swift:68`

The only external reference to the deleted file is `CodexRolloutDiscovery.defaultRootURL`. Replace it with the literal path.

- [ ] **Step 1: Replace the reference**

In `CodexUsage.swift`, change line 68 from:

```swift
static let defaultRootURL = CodexRolloutDiscovery.defaultRootURL
```

to:

```swift
static let defaultRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex/sessions", isDirectory: true)
```

- [ ] **Step 2: Commit**

```bash
git add ClaudeIsland/Services/Session/CodexUsage.swift
git commit -m "fix: inline CodexUsageLoader.defaultRootURL after CodexSessionTracking removal"
```

---

### Task 3: Gate `CodexUsageMonitor` on feature flag

**Files:**
- Modify: `ClaudeIsland/Services/Session/CodexUsage.swift:42-62`

The monitor currently starts its timer and fires an initial refresh unconditionally in `init()`. Change it so the timer and refresh only run when Codex is enabled. The gate hasn't been created yet, so use `UserDefaults.standard.bool(forKey: "codexEnabled")` directly — the gate will read the same key.

- [ ] **Step 1: Add start/stop methods and gate init**

Replace the `CodexUsageMonitor` class (lines 42-63) with:

```swift
@MainActor
class CodexUsageMonitor: ObservableObject {
    static let shared = CodexUsageMonitor()

    @Published private(set) var snapshot: CodexUsageSnapshot?
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?

    private init() {}

    func start() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        snapshot = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        snapshot = try? CodexUsageLoader.load()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ClaudeIsland/Services/Session/CodexUsage.swift
git commit -m "refactor: make CodexUsageMonitor start/stop explicit instead of auto-starting"
```

---

### Task 4: Add L10n entry for "Codex Support"

**Files:**
- Modify: `ClaudeIsland/Core/Localization.swift:66`

- [ ] **Step 1: Add the entry after the `hooks` line**

After line 66 (`static var hooks: String { tr("Hooks", "钩子") }`), add:

```swift
    static var codexSupport: String { tr("Codex Support", "Codex 支持") }
```

- [ ] **Step 2: Commit**

```bash
git add ClaudeIsland/Core/Localization.swift
git commit -m "i18n: add Codex Support label"
```

---

### Task 5: Create `CodexFeatureGate`

**Files:**
- Create: `ClaudeIsland/Core/CodexFeatureGate.swift`

- [ ] **Step 1: Write the gate**

```swift
//
//  CodexFeatureGate.swift
//  ClaudeIsland
//
//  Master toggle for all Codex features. Off by default.
//

import Foundation

@MainActor
final class CodexFeatureGate: ObservableObject {
    static let shared = CodexFeatureGate()

    private static let key = "codexEnabled"

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
            if isEnabled { didEnable() } else { didDisable() }
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    /// Called once from AppDelegate.applicationDidFinishLaunching.
    func onLaunch() {
        guard isEnabled else { return }
        CodexHookInstaller.installIfNeeded()
        CodexUsageMonitor.shared.start()
    }

    private func didEnable() {
        CodexHookInstaller.installIfNeeded()
        CodexUsageMonitor.shared.start()
    }

    private func didDisable() {
        CodexHookInstaller.uninstall()
        CodexUsageMonitor.shared.stop()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ClaudeIsland/Core/CodexFeatureGate.swift
git commit -m "feat: add CodexFeatureGate — master toggle for Codex support"
```

---

### Task 6: Wire `AppDelegate` to call the gate on launch

**Files:**
- Modify: `ClaudeIsland/App/AppDelegate.swift:27-28`

- [ ] **Step 1: Add the gate call**

After line 27 (`HookInstaller.installIfNeeded()`), add:

```swift
        CodexFeatureGate.shared.onLaunch()
```

- [ ] **Step 2: Commit**

```bash
git add ClaudeIsland/App/AppDelegate.swift
git commit -m "feat: wire CodexFeatureGate.onLaunch into app startup"
```

---

### Task 7: Add Codex Support toggle to General tab

**Files:**
- Modify: `ClaudeIsland/UI/Views/SystemSettingsView.swift:381-409`

- [ ] **Step 1: Add `@ObservedObject` for the gate**

In the `GeneralTab` struct, after line 383 (`@State private var launchAtLogin = ...`), add:

```swift
    @ObservedObject private var codexGate = CodexFeatureGate.shared
```

- [ ] **Step 2: Add the toggle to the grid**

After the Hooks `TabToggle` closing brace (line 408), add a third toggle inside the `LazyVGrid`:

```swift
                    TabToggle(icon: "terminal.fill", label: L10n.codexSupport, isOn: codexGate.isEnabled) {
                        codexGate.isEnabled.toggle()
                    }
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/UI/Views/SystemSettingsView.swift
git commit -m "feat: add Codex Support toggle to General settings tab"
```

---

### Task 8: Gate `CodexUsageStatsBar` in `ClaudeInstancesView`

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift:96-107, 267-268, 304`

- [ ] **Step 1: Add `@ObservedObject` for the gate**

After line 304 (`@StateObject private var codexUsageMonitor = CodexUsageMonitor.shared`), add:

```swift
    @ObservedObject private var codexGate = CodexFeatureGate.shared
```

- [ ] **Step 2: Gate the notch overlay Codex bar (lines 96-107)**

Wrap the existing condition. Change line 97 from:

```swift
                if !showBuddyCard && !(sortedInstances.count > 4 && viewModel.isInstancesExpanded)
                    && notchStore.customization.showUsageBar {
```

to:

```swift
                if codexGate.isEnabled && !showBuddyCard && !(sortedInstances.count > 4 && viewModel.isInstancesExpanded)
                    && notchStore.customization.showUsageBar {
```

- [ ] **Step 3: Gate the empty-state Codex bar (lines 267-268)**

Wrap lines 267-268. Change from:

```swift
                    CodexUsageStatsBar(monitor: codexUsageMonitor)
                        .padding(.top, 4)
```

to:

```swift
                    if codexGate.isEnabled {
                        CodexUsageStatsBar(monitor: codexUsageMonitor)
                            .padding(.top, 4)
                    }
```

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "feat: gate CodexUsageStatsBar on CodexFeatureGate.isEnabled"
```

---

## Verification

After all tasks, push to `main` (or open a PR) and confirm the GitHub Actions build succeeds. The toggle should:

1. Default to OFF — no Codex hooks installed, no usage bar visible
2. When toggled ON — installs hooks, starts usage monitor, shows Codex usage bar
3. When toggled OFF — uninstalls hooks, stops monitor, hides bar; existing sessions remain until they expire
