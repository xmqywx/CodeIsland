# Per-Screen Notch Height Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to customize the closed-state notch height on external displays, with all geometry settings (width, offset, height) stored per-screen.

**Architecture:** Extract geometry fields from `NotchCustomization` into a new `ScreenGeometry` struct stored in a `[String: ScreenGeometry]` dictionary keyed by `CGDirectDisplayID`. Add `persistentID` to `NSScreen`. Add ▲▼ height controls to Live Edit overlay. Appearance settings remain global.

**Tech Stack:** Swift, SwiftUI, AppKit, Combine, UserDefaults (JSON-encoded)

---

### Task 1: Add `ScreenGeometry` struct and refactor `NotchCustomization` model

**Files:**
- Modify: `ClaudeIsland/Models/NotchCustomization.swift`

- [ ] **Step 1: Write failing tests for the new model**

Add to `ClaudeIslandTests/NotchCustomizationTests.swift`:

```swift
// MARK: - ScreenGeometry

func test_screenGeometry_defaultValues() {
    let geo = ScreenGeometry.default
    XCTAssertEqual(geo.maxWidth, 440)
    XCTAssertEqual(geo.horizontalOffset, 0)
    XCTAssertEqual(geo.notchHeight, 38)
}

func test_screenGeometry_codableRoundtrip() throws {
    var geo = ScreenGeometry.default
    geo.maxWidth = 520
    geo.horizontalOffset = -42
    geo.notchHeight = 50
    let data = try JSONEncoder().encode(geo)
    let decoded = try JSONDecoder().decode(ScreenGeometry.self, from: data)
    XCTAssertEqual(decoded, geo)
}

// MARK: - Per-screen geometry

func test_geometry_forUnknownScreen_returnsDefault() {
    let c = NotchCustomization.default
    let geo = c.geometry(for: "999")
    XCTAssertEqual(geo, ScreenGeometry.default)
}

func test_updateGeometry_storesPerScreen() {
    var c = NotchCustomization.default
    c.updateGeometry(for: "42") { $0.notchHeight = 60 }
    XCTAssertEqual(c.geometry(for: "42").notchHeight, 60)
    // Other screens still get default
    XCTAssertEqual(c.geometry(for: "99").notchHeight, 38)
}

func test_codable_legacyMigration_topLevelFieldsToDefaultGeometry() throws {
    // Simulate a legacy v1 blob with top-level maxWidth + horizontalOffset
    let legacy = """
    {"theme":"classic","fontScale":"default","showBuddy":true,"showUsageBar":true,
     "maxWidth":520,"horizontalOffset":-30,"hardwareNotchMode":"auto"}
    """
    let decoded = try JSONDecoder().decode(NotchCustomization.self, from: Data(legacy.utf8))
    XCTAssertEqual(decoded.defaultGeometry.maxWidth, 520)
    XCTAssertEqual(decoded.defaultGeometry.horizontalOffset, -30)
    XCTAssertEqual(decoded.defaultGeometry.notchHeight, 38)
    // screenGeometries should be empty (no per-screen data in legacy)
    XCTAssertTrue(decoded.screenGeometries.isEmpty)
}

func test_codable_newFormat_roundtrip() throws {
    var original = NotchCustomization.default
    original.updateGeometry(for: "42") { $0.maxWidth = 600; $0.notchHeight = 50 }
    original.updateGeometry(for: "99") { $0.horizontalOffset = 20 }
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)
    XCTAssertEqual(decoded, original)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -only-testing ClaudeIslandTests/NotchCustomizationTests 2>&1 | tail -20`
Expected: Compilation errors — `ScreenGeometry` not defined.

- [ ] **Step 3: Implement `ScreenGeometry` and refactor `NotchCustomization`**

In `ClaudeIsland/Models/NotchCustomization.swift`, add `ScreenGeometry` before `NotchCustomization`:

```swift
/// Per-screen geometry settings. Keyed by screen's CGDirectDisplayID
/// in NotchCustomization.screenGeometries.
struct ScreenGeometry: Codable, Equatable {
    var maxWidth: CGFloat = 440
    var horizontalOffset: CGFloat = 0
    var notchHeight: CGFloat = 38

    static let `default` = ScreenGeometry()
}
```

Then refactor `NotchCustomization`:

1. **Remove** the `maxWidth` and `horizontalOffset` stored properties.
2. **Remove** them from the `init(...)` parameter list.
3. **Add** these new stored properties:

```swift
    // Geometry (per-screen)
    var screenGeometries: [String: ScreenGeometry] = [:]
    var defaultGeometry: ScreenGeometry = .init()
```

4. **Add** convenience accessors:

```swift
    func geometry(for screenID: String) -> ScreenGeometry {
        screenGeometries[screenID] ?? defaultGeometry
    }

    mutating func updateGeometry(for screenID: String, _ body: (inout ScreenGeometry) -> Void) {
        var geo = geometry(for: screenID)
        body(&geo)
        screenGeometries[screenID] = geo
    }
```

5. **Update** `CodingKeys` — remove `maxWidth`, `horizontalOffset`; add `screenGeometries`, `defaultGeometry`.

6. **Update** `init(from decoder:)` for forward-compat + legacy migration:

```swift
    private enum CodingKeys: String, CodingKey {
        case theme, fontScale, showBuddy, showUsageBar,
             hardwareNotchMode, screenGeometries, defaultGeometry,
             maxWidth, horizontalOffset // legacy keys for migration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try c.decodeIfPresent(NotchThemeID.self, forKey: .theme) ?? .classic
        self.fontScale = try c.decodeIfPresent(FontScale.self, forKey: .fontScale) ?? .default
        self.showBuddy = try c.decodeIfPresent(Bool.self, forKey: .showBuddy) ?? true
        self.showUsageBar = try c.decodeIfPresent(Bool.self, forKey: .showUsageBar) ?? true
        self.hardwareNotchMode = try c.decodeIfPresent(HardwareNotchMode.self, forKey: .hardwareNotchMode) ?? .auto
        self.screenGeometries = try c.decodeIfPresent([String: ScreenGeometry].self, forKey: .screenGeometries) ?? [:]
        self.defaultGeometry = try c.decodeIfPresent(ScreenGeometry.self, forKey: .defaultGeometry) ?? .init()

        // Legacy migration: old top-level geometry fields → defaultGeometry
        if let legacyWidth = try c.decodeIfPresent(CGFloat.self, forKey: .maxWidth) {
            self.defaultGeometry.maxWidth = legacyWidth
        }
        if let legacyOffset = try c.decodeIfPresent(CGFloat.self, forKey: .horizontalOffset) {
            self.defaultGeometry.horizontalOffset = legacyOffset
        }
    }

    // Only encode new fields (legacy keys are never written back)
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(theme, forKey: .theme)
        try c.encode(fontScale, forKey: .fontScale)
        try c.encode(showBuddy, forKey: .showBuddy)
        try c.encode(showUsageBar, forKey: .showUsageBar)
        try c.encode(hardwareNotchMode, forKey: .hardwareNotchMode)
        try c.encode(screenGeometries, forKey: .screenGeometries)
        try c.encode(defaultGeometry, forKey: .defaultGeometry)
    }
```

- [ ] **Step 4: Fix existing tests that reference old `maxWidth` / `horizontalOffset` top-level properties**

In `NotchCustomizationTests.swift`:
- `test_default_hasExpectedValues`: Replace `c.maxWidth` → `c.defaultGeometry.maxWidth`, `c.horizontalOffset` → `c.defaultGeometry.horizontalOffset`.
- `test_codable_roundtripPreservesAllFields`: Replace `original.maxWidth = 520` → `original.defaultGeometry.maxWidth = 520`, `original.horizontalOffset = -42` → `original.defaultGeometry.horizontalOffset = -42`.
- `test_codable_forwardCompat_missingFieldsUseDefaults`: Replace `decoded.maxWidth` → `decoded.defaultGeometry.maxWidth`, `decoded.horizontalOffset` → `decoded.defaultGeometry.horizontalOffset`.

In `NotchCustomizationStoreTests.swift`:
- `test_init_withExistingV1Key_loadsIt`: Replace `persisted.maxWidth = 520` → `persisted.defaultGeometry.maxWidth = 520`, `store.customization.maxWidth` → `store.customization.defaultGeometry.maxWidth`.
- `test_cancelEdit_rollsBackToSnapshot`: Replace all `$0.maxWidth` → `$0.defaultGeometry.maxWidth`, `store.customization.maxWidth` → `store.customization.defaultGeometry.maxWidth`.
- `test_commitEdit_keepsChanges`: Same pattern.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -only-testing ClaudeIslandTests/NotchCustomizationTests -only-testing ClaudeIslandTests/NotchCustomizationStoreTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add ClaudeIsland/Models/NotchCustomization.swift ClaudeIslandTests/NotchCustomizationTests.swift ClaudeIslandTests/NotchCustomizationStoreTests.swift
git commit -m "feat: add ScreenGeometry struct, per-screen geometry storage with legacy migration"
```

---

### Task 2: Add `NSScreen.persistentID` and height clamping

**Files:**
- Modify: `ClaudeIsland/Core/Ext+NSScreen.swift`
- Modify: `ClaudeIsland/Core/NotchHardwareDetector.swift`
- Modify: `ClaudeIslandTests/AutoWidthTests.swift`

- [ ] **Step 1: Write failing tests for height clamping**

Add to `ClaudeIslandTests/AutoWidthTests.swift`:

```swift
// MARK: - clampedHeight

func test_clampedHeight_withinRange_passesThrough() {
    XCTAssertEqual(NotchHardwareDetector.clampedHeight(50), 50)
}

func test_clampedHeight_belowMin_returnsMin() {
    XCTAssertEqual(NotchHardwareDetector.clampedHeight(5), NotchHardwareDetector.minNotchHeight)
}

func test_clampedHeight_aboveMax_returnsMax() {
    XCTAssertEqual(NotchHardwareDetector.clampedHeight(200), NotchHardwareDetector.maxNotchHeight)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -only-testing ClaudeIslandTests/AutoWidthTests 2>&1 | tail -20`
Expected: Compilation errors — `clampedHeight`, `minNotchHeight`, `maxNotchHeight` not defined.

- [ ] **Step 3: Add `persistentID` to NSScreen**

In `ClaudeIsland/Core/Ext+NSScreen.swift`, add after the `hasPhysicalNotch` property:

```swift
    /// Stable string identifier for per-screen settings persistence.
    /// Derived from CGDirectDisplayID.
    var persistentID: String {
        let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        return String(id)
    }
```

- [ ] **Step 4: Add height clamping to NotchHardwareDetector**

In `ClaudeIsland/Core/NotchHardwareDetector.swift`, add after the `minIdleWidth` constant:

```swift
    // MARK: - Notch height clamp

    /// Minimum custom notch height — ensures the notch is always visible.
    static let minNotchHeight: CGFloat = 20

    /// Maximum custom notch height — prevents excessive screen coverage.
    static let maxNotchHeight: CGFloat = 80

    /// Clamp a user-provided notch height to the valid range. Pure function.
    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        max(minNotchHeight, min(height, maxNotchHeight))
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -only-testing ClaudeIslandTests/AutoWidthTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add ClaudeIsland/Core/Ext+NSScreen.swift ClaudeIsland/Core/NotchHardwareDetector.swift ClaudeIslandTests/AutoWidthTests.swift
git commit -m "feat: add NSScreen.persistentID and notch height clamping"
```

---

### Task 3: Add `updateGeometry` to `NotchCustomizationStore`

**Files:**
- Modify: `ClaudeIsland/Services/State/NotchCustomizationStore.swift`
- Modify: `ClaudeIslandTests/NotchCustomizationStoreTests.swift`

- [ ] **Step 1: Write failing test**

Add to `ClaudeIslandTests/NotchCustomizationStoreTests.swift`:

```swift
func test_updateGeometry_mutatesAndPersists() throws {
    let store = NotchCustomizationStore()
    store.updateGeometry(for: "42") { $0.notchHeight = 55 }

    XCTAssertEqual(store.customization.geometry(for: "42").notchHeight, 55)

    let data = try XCTUnwrap(UserDefaults.standard.data(forKey: v1Key))
    let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)
    XCTAssertEqual(decoded.geometry(for: "42").notchHeight, 55)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -only-testing ClaudeIslandTests/NotchCustomizationStoreTests/test_updateGeometry_mutatesAndPersists 2>&1 | tail -20`
Expected: Compilation error — `updateGeometry(for:_:)` not defined on store.

- [ ] **Step 3: Add `updateGeometry` method**

In `ClaudeIsland/Services/State/NotchCustomizationStore.swift`, add after the existing `update(_:)` method:

```swift
    /// Convenience for updating geometry of a specific screen.
    func updateGeometry(for screenID: String, _ mutation: (inout ScreenGeometry) -> Void) {
        update { $0.updateGeometry(for: screenID, mutation) }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -only-testing ClaudeIslandTests/NotchCustomizationStoreTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/Services/State/NotchCustomizationStore.swift ClaudeIslandTests/NotchCustomizationStoreTests.swift
git commit -m "feat: add updateGeometry(for:) convenience on NotchCustomizationStore"
```

---

### Task 4: Wire per-screen geometry into `NotchWindowController` and `NotchViewModel`

**Files:**
- Modify: `ClaudeIsland/UI/Window/NotchWindowController.swift`
- Modify: `ClaudeIsland/Core/NotchViewModel.swift`

- [ ] **Step 1: Add `screenID` to `NotchWindowController`**

In `NotchWindowController.swift`, add a stored property after `private let screen: NSScreen`:

```swift
    let screenID: String
```

In `init(screen:)`, after `self.screen = screen`, add:

```swift
        self.screenID = screen.persistentID
```

- [ ] **Step 2: Update `applyGeometryFromStore()` to use per-screen geometry**

Replace the body of `applyGeometryFromStore()`:

```swift
    @MainActor
    func applyGeometryFromStore() {
        let store = NotchCustomizationStore.shared
        let geo = store.customization.geometry(for: screenID)
        let window = self.window

        guard let window else { return }
        let activeScreen = window.screen ?? self.screen
        let screenFrame = activeScreen.frame

        let runtimeWidth = NotchHardwareDetector.clampedWidth(
            measuredContentWidth: geo.maxWidth,
            maxWidth: geo.maxWidth
        )
        let clampedOffset = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: runtimeWidth,
            screenWidth: screenFrame.width
        )
        let baseX = (screenFrame.width - runtimeWidth) / 2
        let finalX = screenFrame.origin.x + baseX + clampedOffset

        _ = (finalX, runtimeWidth)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(window.frame, display: true)
        }
    }
```

- [ ] **Step 3: Pass `screenID` into Live Edit overlay**

In `enterLiveEditMode()`, update the `NotchLiveEditOverlay` initializer to pass the screenID:

```swift
        let overlay = NotchLiveEditOverlay(
            screenID: screenID,
            screenProvider: { activeScreen },
            onExit: { [weak self] in
                self?.exitLiveEditMode()
            }
        )
```

- [ ] **Step 4: Update `NotchViewModel` to accept `screenID`**

In `NotchViewModel.swift`:

Add a stored property:

```swift
    let screenID: String
```

Update `init` signature and body:

```swift
    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool, screenID: String) {
        self.screenID = screenID
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
        observeSelectors()
    }
```

Update `currentHorizontalOffset` to read per-screen:

```swift
    private var currentHorizontalOffset: CGFloat {
        let geo = NotchCustomizationStore.shared.customization.geometry(for: screenID)
        let runtime: CGFloat = status == .opened ? openedSize.width : (geometry.deviceNotchRect.width + currentExpansionWidth)
        return NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: runtime,
            screenWidth: geometry.screenRect.width
        )
    }
```

- [ ] **Step 5: Update `NotchWindowController.init` to pass `screenID`**

In `NotchWindowController.swift`, update the `NotchViewModel` creation:

```swift
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch,
            screenID: screen.persistentID
        )
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild build -project ClaudeIsland.xcodeproj -scheme ClaudeIsland 2>&1 | tail -20`
Expected: Build succeeds (ignoring NotchLiveEditOverlay signature mismatch — fixed in Task 6).

- [ ] **Step 7: Commit**

```bash
git add ClaudeIsland/UI/Window/NotchWindowController.swift ClaudeIsland/Core/NotchViewModel.swift
git commit -m "feat: wire per-screen geometry into window controller and view model"
```

---

### Task 5: Update `NotchView` to read per-screen geometry

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`

- [ ] **Step 1: Update `closedNotchSize` to use per-screen `notchHeight`**

The `closedNotchSize` computed property currently reads `viewModel.deviceNotchRect.height`. Change it to use the per-screen configured height for non-hardware-notch screens:

```swift
    private var closedNotchSize: CGSize {
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        let height: CGFloat
        if viewModel.hasPhysicalNotch {
            height = viewModel.deviceNotchRect.height
        } else {
            height = NotchHardwareDetector.clampedHeight(geo.notchHeight)
        }
        return CGSize(
            width: viewModel.deviceNotchRect.width,
            height: height
        )
    }
```

- [ ] **Step 2: Update `expansionWidth` to use per-screen `maxWidth`**

```swift
    private var expansionWidth: CGFloat {
        guard hasActiveSessions else { return 0 }
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        let userMax = geo.maxWidth
        let userExpansion = max(0, userMax - closedNotchSize.width)
        if compactCollapsed {
            return min(100, userExpansion)
        }
        return userExpansion
    }
```

- [ ] **Step 3: Update `clampedHorizontalOffset` to use per-screen offset**

```swift
    private var clampedHorizontalOffset: CGFloat {
        let geo = notchStore.customization.geometry(for: viewModel.screenID)
        return NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: geo.horizontalOffset,
            runtimeWidth: viewModel.status == .opened ? notchSize.width : closedContentWidth,
            screenWidth: viewModel.screenRect.width
        )
    }
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -project ClaudeIsland.xcodeproj -scheme ClaudeIsland 2>&1 | tail -20`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/UI/Views/NotchView.swift
git commit -m "feat: NotchView reads per-screen geometry for height, width, and offset"
```

---

### Task 6: Update Live Edit overlay with height controls and per-screen writes

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchLiveEditOverlay.swift`
- Modify: `ClaudeIsland/Core/Localization.swift`

- [ ] **Step 1: Add `screenID` property to `NotchLiveEditOverlay`**

Add a stored property at the top of the struct, before `@ObservedObject`:

```swift
    let screenID: String
```

- [ ] **Step 2: Update `visibleNotchHeight` to read from per-screen config**

Replace the hardcoded `visibleNotchHeight` constant with a computed property:

```swift
    private var visibleNotchHeight: CGFloat {
        if hasHardwareNotch {
            return 38
        }
        let geo = store.customization.geometry(for: screenID)
        return NotchHardwareDetector.clampedHeight(geo.notchHeight)
    }
```

- [ ] **Step 3: Update `userExpansion` and `readoutText` to read per-screen**

```swift
    private var userExpansion: CGFloat {
        let geo = store.customization.geometry(for: screenID)
        return max(0, geo.maxWidth - baseNotchWidth)
    }
```

Update `readoutText` to include height:

```swift
    private var readoutText: String {
        let geo = store.customization.geometry(for: screenID)
        let width = Int(geo.maxWidth.rounded())
        let height = Int(visibleNotchHeight.rounded())
        let offset = Int(geo.horizontalOffset.rounded())
        let offsetSign = offset > 0 ? "+\(offset)" : "\(offset)"
        return "W \(width)pt   H \(height)pt   X \(offsetSign)pt"
    }
```

- [ ] **Step 4: Add ▲▼ height arrow buttons to the body**

In the `ZStack` of `body`, after the existing ◀ ▶ arrow buttons (items 4), add:

```swift
                // 4b. Height arrow buttons (▲ ▼) above/below the notch.
                // Disabled when screen has a hardware notch.
                heightArrowButton(direction: +1, label: "Increase notch height")
                    .position(x: notchCenterX, y: -10)

                heightArrowButton(direction: -1, label: "Decrease notch height")
                    .position(x: notchCenterX, y: visibleNotchHeight + 14)
```

- [ ] **Step 5: Implement `heightArrowButton` and `applyHeightStep`**

Add after the existing `arrowButton(direction:label:)` method:

```swift
    private func heightArrowButton(direction: Int, label: String) -> some View {
        Button {
            applyHeightStep(direction: direction)
        } label: {
            Image(systemName: direction > 0 ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(hasHardwareNotch ? .white.opacity(0.35) : .black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hasHardwareNotch ? Color.black.opacity(0.5) : neonGreen))
                .shadow(color: hasHardwareNotch ? .clear : neonGreen.opacity(0.45), radius: 6)
        }
        .buttonStyle(.plain)
        .disabled(hasHardwareNotch)
        .accessibilityLabel(label)
        .accessibilityHint(hasHardwareNotch ? "Disabled: hardware notch height is fixed" : "Hold Command for a larger step, hold Option for a finer step.")
    }

    private func applyHeightStep(direction: Int) {
        let flags = NSEvent.modifierFlags
        let step: CGFloat
        if flags.contains(.command) {
            step = 10
        } else if flags.contains(.option) {
            step = 1
        } else {
            step = 4
        }
        store.updateGeometry(for: screenID) { geo in
            geo.notchHeight = NotchHardwareDetector.clampedHeight(
                geo.notchHeight + CGFloat(direction) * step
            )
        }
    }
```

- [ ] **Step 6: Update existing width arrow and drag to write per-screen**

Update `applyArrowStep(direction:)`:

```swift
    private func applyArrowStep(direction: Int) {
        let flags = NSEvent.modifierFlags
        let step: CGFloat
        if flags.contains(.command) {
            step = 10
        } else if flags.contains(.option) {
            step = 1
        } else {
            step = 4
        }
        store.updateGeometry(for: screenID) { geo in
            geo.maxWidth = max(
                NotchHardwareDetector.minIdleWidth,
                geo.maxWidth + CGFloat(direction) * step
            )
        }
    }
```

Update the drag gesture `.onChanged` closure:

```swift
                            .onChanged { value in
                                if dragStartOffset == nil {
                                    dragStartOffset = store.customization.geometry(for: screenID).horizontalOffset
                                }
                                let start = dragStartOffset ?? 0
                                store.updateGeometry(for: screenID) { geo in
                                    geo.horizontalOffset = start + value.translation.width
                                }
                            }
```

Update `applyNotchPreset()`:

```swift
    private func applyNotchPreset() {
        let width = NotchHardwareDetector.hardwareNotchWidth(
            on: screenProvider(),
            mode: store.customization.hardwareNotchMode
        )
        guard width > 0 else { return }
        store.updateGeometry(for: screenID) { geo in
            geo.maxWidth = width + 20
            geo.horizontalOffset = 0
        }
        withAnimation(.easeIn(duration: 0.2)) {
            presetMarkerVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                presetMarkerVisible = false
            }
        }
    }
```

Update the Reset button action:

```swift
                        actionButton(
                            title: L10n.notchEditReset,
                            icon: "arrow.counterclockwise",
                            enabled: true
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                store.updateGeometry(for: screenID) { geo in
                                    geo.maxWidth = ScreenGeometry.default.maxWidth
                                    geo.horizontalOffset = ScreenGeometry.default.horizontalOffset
                                    geo.notchHeight = ScreenGeometry.default.notchHeight
                                }
                                subMode = .resize
                                dragStartOffset = nil
                            }
                        }
```

- [ ] **Step 7: Build to verify compilation**

Run: `xcodebuild build -project ClaudeIsland.xcodeproj -scheme ClaudeIsland 2>&1 | tail -20`
Expected: Build succeeds.

- [ ] **Step 8: Commit**

```bash
git add ClaudeIsland/UI/Views/NotchLiveEditOverlay.swift
git commit -m "feat: add height ▲▼ controls to Live Edit, convert all geometry ops to per-screen"
```

---

### Task 7: Fix remaining compile errors across the codebase

**Files:**
- Any file that still references `customization.maxWidth` or `customization.horizontalOffset` directly

- [ ] **Step 1: Search for remaining references to old top-level geometry fields**

Run: `grep -rn 'customization\.maxWidth\|customization\.horizontalOffset\|\.maxWidth\b.*=\|\.horizontalOffset\b.*=' ClaudeIsland/ --include='*.swift' | grep -v 'ScreenGeometry\|defaultGeometry\|screenGeometries'`

This will find any remaining direct references to the old fields.

- [ ] **Step 2: Fix each reference**

For each hit, determine the screenID context and convert to per-screen access:
- If in a view/controller that has access to `screenID` → use `customization.geometry(for: screenID).maxWidth`
- If in a context without screenID → determine the correct screen and pass it through

Common patterns:
- `store.customization.maxWidth` → `store.customization.geometry(for: screenID).maxWidth`
- `$0.maxWidth = ...` → use `store.updateGeometry(for: screenID) { $0.maxWidth = ... }`

- [ ] **Step 3: Build to verify clean compilation**

Run: `xcodebuild build -project ClaudeIsland.xcodeproj -scheme ClaudeIsland 2>&1 | tail -20`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "fix: resolve remaining references to old top-level geometry fields"
```

---

### Task 8: Run all tests and verify

**Files:**
- All test files

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -project ClaudeIsland.xcodeproj -scheme ClaudeIsland 2>&1 | tail -40`
Expected: All tests PASS.

- [ ] **Step 2: Fix any failures**

If any tests fail, fix them by updating to use per-screen geometry access patterns.

- [ ] **Step 3: Final commit**

```bash
git add -u
git commit -m "test: all tests pass with per-screen geometry model"
```
