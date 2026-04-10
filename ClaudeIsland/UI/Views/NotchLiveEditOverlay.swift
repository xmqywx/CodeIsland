//
//  NotchLiveEditOverlay.swift
//  ClaudeIsland
//
//  SwiftUI content for the NotchLiveEditPanel. Lays out floating
//  controls — arrow buttons, Notch Preset, Drag Mode, Save / Cancel
//  — at absolute positions computed around the REAL on-screen notch
//  rather than as a separate mocked-up notch in the panel center.
//
//  Coordinate model:
//  - The hosting panel covers the full screen width at the top of
//    the active screen. So panel x=0 corresponds to the screen's
//    left edge and the screen's mid X is panel.size.width/2.
//  - The visible notch is rendered by NotchView at screen-mid plus
//    the per-screen `ScreenGeometry.horizontalOffset`. We mirror that math here so
//    the dashed border, drag-catcher, and arrow buttons all align
//    pixel-for-pixel with the real notch.
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  section 4.2.
//

import AppKit
import SwiftUI

enum NotchEditSubMode {
    case resize
    case drag
}

struct NotchLiveEditOverlay: View {
    let screenID: String
    @ObservedObject private var store: NotchCustomizationStore = .shared
    @State private var subMode: NotchEditSubMode = .resize
    @State private var presetMarkerVisible: Bool = false

    /// Offset captured at the start of a drag gesture so deltas
    /// accumulate from the committed store value rather than from
    /// zero on every onChanged callback. Spec 5.5.
    @State private var dragStartOffset: CGFloat? = nil

    /// Closure that returns the screen the live edit panel was
    /// created for. We pass this in instead of reading
    /// `NSScreen.main` because once the live edit panel becomes
    /// key, `NSScreen.main` can flip to a non-notched secondary
    /// display on multi-monitor setups, which makes
    /// `NotchHardwareDetector.hasHardwareNotch(...)` return false
    /// even on a notched MacBook Pro and the "贴合刘海" button
    /// gets disabled by accident.
    var screenProvider: () -> NSScreen? = { NSScreen.main }

    /// Callback fired when the user commits or cancels the edit
    /// session, so the controller that created the panel can tear
    /// down the window.
    var onExit: () -> Void = {}

    private let neonGreen = Color(hex: "CAFF00")
    private let neonPink  = Color(hex: "FB7185")

    /// Approximate visible notch height. The hardware notch is
    /// ~37pt; in opened state the panel is much taller, but for
    /// edit-mode visuals (dashed border + drag-catcher) we anchor
    /// to the closed-state height so the interactive region matches
    /// the resting visual.
    private var visibleNotchHeight: CGFloat {
        if hasHardwareNotch {
            return 38
        }
        let geo = store.customization.geometry(for: screenID)
        return NotchHardwareDetector.clampedHeight(geo.notchHeight)
    }

    /// Hardware notch width on the active screen, honoring the
    /// `hardwareNotchMode` override. Falls back to 200pt for the
    /// virtual / no-notch case so the visible notch never collapses
    /// to zero in the editor.
    private var baseNotchWidth: CGFloat {
        let hw = NotchHardwareDetector.hardwareNotchWidth(
            on: screenProvider(),
            mode: store.customization.hardwareNotchMode
        )
        return hw > 0 ? hw : 200
    }

    /// User-controlled wing expansion derived from `maxWidth`.
    private var userExpansion: CGFloat {
        let geo = store.customization.geometry(for: screenID)
        return max(0, geo.maxWidth - baseNotchWidth)
    }

    /// Total visible notch width (hardware width + wings).
    private var visibleNotchWidth: CGFloat {
        baseNotchWidth + userExpansion
    }

    private var hasHardwareNotch: Bool {
        NotchHardwareDetector.hasHardwareNotch(
            on: screenProvider(),
            mode: store.customization.hardwareNotchMode
        )
    }

    /// Live numeric readout shown below the notch as the user drags.
    /// Width is the current `maxWidth` so the arrow buttons feed
    /// directly into it; offset is the signed clamped value so the
    /// user can tell when they've dragged off-center. Both rounded
    /// to whole points for legibility.
    private var readoutText: String {
        let geo = store.customization.geometry(for: screenID)
        let width = Int(geo.maxWidth.rounded())
        let height = Int(visibleNotchHeight.rounded())
        let offset = Int(geo.horizontalOffset.rounded())
        let offsetSign = offset > 0 ? "+\(offset)" : "\(offset)"
        return "W \(width)pt   H \(height)pt   X \(offsetSign)pt"
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = proxy.size.width

            // Mirror the same clamp NotchView applies for `.offset(x:)`.
            let clampedOffset = NotchHardwareDetector.clampedHorizontalOffset(
                storedOffset: store.customization.geometry(for: screenID).horizontalOffset,
                runtimeWidth: visibleNotchWidth,
                screenWidth: panelWidth
            )

            let notchCenterX = panelWidth / 2 + clampedOffset
            let notchLeftX = notchCenterX - visibleNotchWidth / 2
            let notchRightX = notchCenterX + visibleNotchWidth / 2
            let notchVerticalCenter = visibleNotchHeight / 2 + 4

            ZStack(alignment: .topLeading) {
                // 1. Soft neon-green dashed border tracing the real
                //    notch position. Pulses subtly to indicate edit
                //    mode is live.
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        neonGreen.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                    .frame(
                        width: visibleNotchWidth + 8,
                        height: visibleNotchHeight + 8
                    )
                    .shadow(color: neonGreen.opacity(0.25), radius: 8)
                    .position(x: notchCenterX, y: notchVerticalCenter)
                    .accessibilityHidden(true)

                // 2. Notch Preset width marker — a dashed underline
                //    that flashes when the user clicks Notch Preset.
                if presetMarkerVisible && hasHardwareNotch {
                    let markerY = visibleNotchHeight + 12
                    let markerWidth = NotchHardwareDetector.hardwareNotchWidth(
                        on: screenProvider(),
                        mode: store.customization.hardwareNotchMode
                    )
                    Rectangle()
                        .fill(neonGreen)
                        .frame(width: markerWidth, height: 2)
                        .overlay(
                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                                .foregroundStyle(neonGreen)
                        )
                        .position(x: notchCenterX, y: markerY)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }

                // 3. Drag-catcher rectangle. Only present in drag
                //    sub-mode, sized to (and positioned over) the
                //    visible notch. Captures the SwiftUI DragGesture
                //    used to mutate `horizontalOffset` in real time.
                if subMode == .drag {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(
                            width: visibleNotchWidth + 16,
                            height: visibleNotchHeight + 12
                        )
                        .position(x: notchCenterX, y: notchVerticalCenter)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if dragStartOffset == nil {
                                        dragStartOffset = store.customization.geometry(for: screenID).horizontalOffset
                                    }
                                    let start = dragStartOffset ?? 0
                                    store.updateGeometry(for: screenID) { geo in
                                        geo.horizontalOffset = start + value.translation.width
                                    }
                                }
                                .onEnded { _ in
                                    dragStartOffset = nil
                                }
                        )
                }

                // 4. Arrow buttons (◀ ▶) hugging the left and right
                //    edges of the visible notch. Symmetric resize.
                arrowButton(direction: -1, label: "Shrink notch")
                    .position(x: notchLeftX - 28, y: notchVerticalCenter)

                arrowButton(direction: +1, label: "Grow notch")
                    .position(x: notchRightX + 28, y: notchVerticalCenter)

                // 4b. Height arrow buttons (▼ ▲) below the notch.
                // Left: decrease height, Right: increase height.
                heightArrowButton(direction: -1, label: "Decrease notch height")
                    .position(x: notchCenterX - 22, y: visibleNotchHeight + 14)

                heightArrowButton(direction: +1, label: "Increase notch height")
                    .position(x: notchCenterX + 22, y: visibleNotchHeight + 14)

                // 5. Live width + offset readout — small monospaced
                //    label below the height arrows so it doesn't overlap.
                Text(readoutText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.black.opacity(0.6))
                    )
                    .position(x: notchCenterX, y: visibleNotchHeight + 44)
                    .accessibilityHidden(true)

                // 6. Action row + Reset + Save/Cancel — stacked
                //    vertically below the notch, horizontally
                //    centered on the notch.
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton(
                            title: L10n.notchEditNotchPreset,
                            icon: "scope",
                            enabled: hasHardwareNotch,
                            tooltip: hasHardwareNotch ? nil : L10n.notchEditPresetDisabledTooltip
                        ) {
                            applyNotchPreset()
                        }
                        .accessibilityLabel("Reset to hardware notch width")

                        actionButton(
                            title: L10n.notchEditDragMode,
                            icon: "hand.draw",
                            enabled: true,
                            highlight: subMode == .drag
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                subMode = (subMode == .resize) ? .drag : .resize
                                dragStartOffset = nil
                            }
                        }
                        .accessibilityLabel("Toggle drag mode")
                        .accessibilityValue(subMode == .drag ? "On" : "Off")

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
                        .accessibilityLabel("Reset to default size and position")
                    }

                    HStack(spacing: 12) {
                        Button {
                            store.commitEdit()
                            onExit()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .heavy))
                                Text(L10n.notchEditSave)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(neonGreen))
                            .shadow(color: neonGreen.opacity(0.45), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save notch customization")

                        Button {
                            store.cancelEdit()
                            onExit()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .heavy))
                                Text(L10n.notchEditCancel)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(neonPink))
                            .shadow(color: neonPink.opacity(0.4), radius: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel notch customization")
                    }
                }
                .position(x: notchCenterX, y: visibleNotchHeight + 90)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    // MARK: - Controls

    private func arrowButton(direction: Int, label: String) -> some View {
        Button {
            applyArrowStep(direction: direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 32, height: 32)
                .background(Circle().fill(neonGreen))
                .shadow(color: neonGreen.opacity(0.45), radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Hold Command for a larger step, hold Option for a finer step.")
    }

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
        // Flash the dashed marker for ~2s.
        withAnimation(.easeIn(duration: 0.2)) {
            presetMarkerVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                presetMarkerVisible = false
            }
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        enabled: Bool,
        highlight: Bool = false,
        tooltip: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(enabled ? (highlight ? .black : .white) : .white.opacity(0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(highlight ? neonGreen : Color.black.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(neonGreen.opacity(highlight ? 0 : 0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(tooltip ?? "")
    }
}
