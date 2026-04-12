# Per-Screen Notch Height Customization

## Problem

External 4K displays have no hardware notch. The app currently hardcodes the closed-state notch height to 38pt for all non-notch screens. Users want to adjust this height. Additionally, all geometry settings (width, offset) are global — they should be per-screen so each display can have its own configuration.

## Solution

1. Extract geometry properties (`maxWidth`, `horizontalOffset`, new `notchHeight`) into a `ScreenGeometry` struct stored per-screen in a dictionary keyed by `CGDirectDisplayID`.
2. Add height adjustment controls (▲▼ arrows) to the existing Live Edit mode.
3. Appearance settings (theme, font, visibility toggles, hardware mode) remain global.

## Data Model

### New: `ScreenGeometry`

```swift
struct ScreenGeometry: Codable, Equatable {
    var maxWidth: CGFloat = 440
    var horizontalOffset: CGFloat = 0
    var notchHeight: CGFloat = 38

    static let `default` = ScreenGeometry()
}
```

### Modified: `NotchCustomization`

```swift
struct NotchCustomization: Codable, Equatable {
    // Appearance (global)
    var theme: NotchThemeID = .classic
    var fontScale: FontScale = .default
    var showBuddy: Bool = true
    var showUsageBar: Bool = true
    var hardwareNotchMode: HardwareNotchMode = .auto

    // Geometry (per-screen)
    var screenGeometries: [String: ScreenGeometry] = [:]
    var defaultGeometry: ScreenGeometry = .init()

    func geometry(for screenID: String) -> ScreenGeometry {
        screenGeometries[screenID] ?? defaultGeometry
    }

    mutating func updateGeometry(for screenID: String, _ body: (inout ScreenGeometry) -> Void) {
        var geo = geometry(for: screenID)
        body(&geo)
        screenGeometries[screenID] = geo
    }
}
```

Remove the old top-level `maxWidth` and `horizontalOffset` properties.

### Screen ID

```swift
extension NSScreen {
    var persistentID: String {
        let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        return String(id)
    }
}
```

### Migration (v1 compatible)

In `NotchCustomization.init(from:)`:
- If legacy top-level `maxWidth` or `horizontalOffset` fields exist, read them into `defaultGeometry`.
- New fields (`screenGeometries`, `defaultGeometry`) decode with defaults when absent.
- UserDefaults key stays `"notchCustomization.v1"` — no key bump needed.
- On next save, only new fields are encoded; legacy fields are dropped.

## Geometry Calculation

### `NotchGeometry`

Add `customNotchHeight: CGFloat` field. Methods that reference the notch height (`collapsedScreenRect`, `notchScreenRect`, `isPointInNotch`) use `customNotchHeight` instead of `deviceNotchRect.height` for the collapsed state.

### `NotchHardwareDetector`

New constants and function:

```swift
static let minNotchHeight: CGFloat = 20
static let maxNotchHeight: CGFloat = 80

static func clampedHeight(_ height: CGFloat) -> CGFloat {
    max(minNotchHeight, min(height, maxNotchHeight))
}
```

### `NotchView`

`closedNotchSize.height` reads from `ScreenGeometry.notchHeight` (via `NotchGeometry.customNotchHeight`) instead of `deviceNotchRect.height`.

### Hardware notch override

When the screen has a physical notch (`safeAreaInsets.top > 0`), `customNotchHeight` is ignored — the system value is used. Height controls are disabled in Live Edit for such screens.

## Live Edit Interaction

### Height controls

- ▲▼ arrow buttons positioned above/below the notch (symmetric with existing ◀▶ width arrows).
- Step sizes match width controls:
  - Default: ±4pt
  - `⌘`: ±10pt
  - `⌥`: ±1pt
- Clamped to `[20, 80]` range.
- Disabled when screen has a hardware notch.

### Numeric readout

Updated from `"W 440pt  X +12pt"` to:

```
W 440pt   H 38pt   X +12pt
```

### Per-screen binding

On entering Live Edit, the current screen's `persistentID` is captured. All geometry adjustments (width, height, offset) read/write the `ScreenGeometry` for that screen ID.

## Store Layer

### `NotchCustomizationStore`

- Add convenience method: `updateGeometry(for screenID: String, _ body: (inout ScreenGeometry) -> Void)`.
- Live Edit snapshot/restore unchanged — `editDraftOrigin` snapshots the entire `NotchCustomization` (all screens), cancel restores the whole thing.

## Window Controller

### `NotchWindowController`

- Stores the screen's `persistentID` at init time.
- `applyGeometryFromStore()` reads per-screen geometry via `customization.geometry(for: screenID)`.
- Passes `customNotchHeight` when constructing `NotchGeometry` / `NotchViewModel`.

## Files Changed

| File | Change |
|------|--------|
| `NotchCustomization.swift` | Add `ScreenGeometry`, replace `maxWidth`/`horizontalOffset` with `screenGeometries`/`defaultGeometry`, migration decoding |
| `Ext+NSScreen.swift` | Add `persistentID` |
| `NotchCustomizationStore.swift` | Add `updateGeometry(for:_:)` |
| `NotchGeometry.swift` | Add `customNotchHeight`, use it in collapsed-state methods |
| `NotchHardwareDetector.swift` | Add height constants + `clampedHeight()` |
| `NotchWindowController.swift` | Store screenID, read per-screen geometry |
| `NotchView.swift` | `closedNotchSize` height from config, per-screen reads |
| `NotchLiveEditOverlay.swift` | ▲▼ buttons, `H xxpt` readout, per-screen writes |
| `NotchViewModel.swift` | Pass `customNotchHeight` to geometry |
| Tests | Adapt `NotchCustomizationTests`, `NotchCustomizationStoreTests`, `AutoWidthTests` |

## Not Changed

- Theme, font, visibility toggles, sound — remain global.
- `NotchCustomizationSettingsView` — geometry is adjusted in Live Edit only.
- Opened-state panel heights — content-dependent, not user-adjustable.
