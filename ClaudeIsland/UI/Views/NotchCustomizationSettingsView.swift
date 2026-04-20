//
//  NotchCustomizationSettingsView.swift
//  ClaudeIsland
//
//  Settings UI surface for the notch customization feature, embedded
//  inside the Appearance tab of `SystemSettingsView` (wrapped in a
//  `SettingsCard` with the section title). Renders only the inner
//  rows — no padding, background, or section header of its own —
//  so the visual style matches the surrounding cards exactly.
//
//  The visual constants here are intentionally kept in sync with
//  `SystemSettingsView`'s private `Theme` enum (font sizes 12 for
//  labels, 12 for icons, sidebarFill = #CAFF00 for the lime accent,
//  inner row corner radius 7) so the rows look identical to the
//  TabToggle / SettingsCard rows in the rest of the popup.
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  sections 4.1, 4.5, 4.6.
//

import SwiftUI

struct NotchCustomizationSettingsView: View {
    @ObservedObject private var store: NotchCustomizationStore = .shared

    private static let brandLime = Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)

    var body: some View {
        // The enclosing SettingsCard already provides the title,
        // padding, background, and border. We just emit the rows.
        VStack(alignment: .leading, spacing: 8) {
            themeSection
            buddyStyleRow
            fontSizeRow
            hoverSpeedRow

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                visibilityToggle(
                    icon: "sparkles",
                    label: L10n.notchShowBuddy,
                    isOn: store.customization.showBuddy
                ) {
                    store.update { $0.showBuddy.toggle() }
                }
                .accessibilityLabel(L10n.notchShowBuddy)

                visibilityToggle(
                    icon: "chart.bar.fill",
                    label: L10n.notchShowUsageBar,
                    isOn: store.customization.showUsageBar
                ) {
                    store.update { $0.showUsageBar.toggle() }
                }
                .accessibilityLabel(L10n.notchShowUsageBar)
            }

            hardwareModeRow
            customizeButton
        }
    }

    // MARK: - Theme picker — grid of preview cards

    /// Header row + 2-column grid of theme cards. Each card shows a mini
    /// capsule rendered in the target theme's own colors so the user can
    /// judge the palette at a glance, not just "green dot says Forest".
    /// Selected card glows with its own accent — each theme announces
    /// itself the way the Claude Design mock does.
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 16)
                Text(L10n.notchTheme)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(L10n.notchThemeName(store.customization.theme))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NotchPalette.for(store.customization.theme).accent)
            }
            .padding(.horizontal, 2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                ForEach(NotchThemeID.allCases) { id in
                    ThemePreviewCard(
                        themeID: id,
                        isSelected: store.customization.theme == id
                    ) {
                        store.update { $0.theme = id }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Buddy style segmented picker row

    /// Two-way segmented picker for which sprite appears in the notch:
    /// pixel cat (always available) / Claude Code companion emoji. Emoji
    /// needs `~/.claude.json` to have `companion` data or it falls back
    /// to the pixel cat at render time. The pick also mirrors into the
    /// legacy `usePixelCat` AppStorage so ClaudeInstancesView (which
    /// hasn't been migrated) stays roughly in sync.
    private var buddyStyleRow: some View {
        controlRow(icon: "cat", label: L10n.notchBuddyStyle) {
            HStack(spacing: 0) {
                buddyStyleSegment(.pixelCat, shortLabel: L10n.notchBuddyPixelCat)
                buddyStyleSegment(.emoji,    shortLabel: L10n.notchBuddyEmoji)
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
            )
        }
    }

    private func buddyStyleSegment(
        _ style: BuddyStyle,
        shortLabel: String
    ) -> some View {
        let isSelected = store.customization.buddyStyle == style
        return Button {
            store.update { $0.buddyStyle = style }
            // Keep legacy AppStorage in sync so unmigrated call sites
            // (ClaudeInstancesView) still render something sensible.
            UserDefaults.standard.set(style == .pixelCat, forKey: "usePixelCat")
        } label: {
            Text(shortLabel)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .frame(minWidth: 36)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Self.brandLime : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shortLabel)
    }

    // MARK: - Font size segmented picker row

    private var fontSizeRow: some View {
        controlRow(icon: "textformat.size", label: L10n.notchFontSize) {
            HStack(spacing: 0) {
                fontSizeSegment(.small,   shortLabel: L10n.notchFontSmall,   accessibilityLabel: L10n.notchFontSmallFull)
                fontSizeSegment(.default, shortLabel: L10n.notchFontDefault, accessibilityLabel: L10n.notchFontDefaultFull)
                fontSizeSegment(.large,   shortLabel: L10n.notchFontLarge,   accessibilityLabel: L10n.notchFontLargeFull)
                fontSizeSegment(.xLarge,  shortLabel: L10n.notchFontXLarge,  accessibilityLabel: L10n.notchFontXLargeFull)
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
            )
        }
    }

    private func fontSizeSegment(
        _ scale: FontScale,
        shortLabel: String,
        accessibilityLabel: String
    ) -> some View {
        Button {
            store.update { $0.fontScale = scale }
        } label: {
            Text(shortLabel)
                .font(.system(size: 11, weight: store.customization.fontScale == scale ? .bold : .medium))
                .foregroundColor(store.customization.fontScale == scale ? .black : .white.opacity(0.7))
                .frame(minWidth: 26)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(store.customization.fontScale == scale ? Self.brandLime : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Hover speed segmented picker row

    private var hoverSpeedRow: some View {
        controlRow(icon: "cursorarrow.motionlines", label: L10n.notchHoverSpeed) {
            HStack(spacing: 0) {
                hoverSpeedSegment(.instant, shortLabel: L10n.notchHoverInstant)
                hoverSpeedSegment(.normal,  shortLabel: L10n.notchHoverNormal)
                hoverSpeedSegment(.slow,    shortLabel: L10n.notchHoverSlow)
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
            )
        }
    }

    private func hoverSpeedSegment(
        _ speed: HoverSpeed,
        shortLabel: String
    ) -> some View {
        Button {
            store.update { $0.hoverSpeed = speed }
        } label: {
            Text(shortLabel)
                .font(.system(size: 11, weight: store.customization.hoverSpeed == speed ? .bold : .medium))
                .foregroundColor(store.customization.hoverSpeed == speed ? .black : .white.opacity(0.7))
                .frame(minWidth: 30)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(store.customization.hoverSpeed == speed ? Self.brandLime : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shortLabel)
    }

    // MARK: - Visibility toggle (TabToggle-style)

    private func visibilityToggle(
        icon: String,
        label: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isOn ? 0.9 : 0.5))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundColor(.white.opacity(isOn ? 0.95 : 0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(isOn ? Self.brandLime : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isOn ? Self.brandLime.opacity(0.10) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        isOn ? Self.brandLime.opacity(0.25) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hardware mode picker row

    private var hardwareModeRow: some View {
        controlRow(icon: "laptopcomputer", label: L10n.notchHardwareMode) {
            Menu {
                Button(L10n.notchHardwareAuto) {
                    store.update { $0.hardwareNotchMode = .auto }
                }
                Button(L10n.notchHardwareForceVirtual) {
                    store.update { $0.hardwareNotchMode = .forceVirtual }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(
                        store.customization.hardwareNotchMode == .auto
                            ? L10n.notchHardwareAuto
                            : L10n.notchHardwareForceVirtual
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L10n.notchHardwareMode)
        }
    }

    // MARK: - Customize button — full-width prominent action

    private var customizeButton: some View {
        Button {
            store.enterEditMode()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.notchCustomizeButton)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.85)
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(Self.brandLime)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.notchCustomizeButton)
        .accessibilityHint("Opens live edit mode for resizing and positioning the notch directly.")
    }

    // MARK: - Shared row chrome

    /// A row with an icon + label on the left and trailing content on
    /// the right. Visual constants match `SystemSettingsView.TabToggle`
    /// so themePicker / fontSize / hardwareMode rows share the exact
    /// look of the surrounding tabs.
    private func controlRow<Trailing: View>(
        icon: String,
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Theme preview card

/// One cell in the theme grid. Shows a miniature pill rendered in the
/// target theme's palette: accent dot + status dot + "空闲" text + "×1"
/// badge, matching the real notch's idle-state layout so the swatch
/// communicates how the theme reads in situ. Selected cards glow in
/// their own accent color (each theme announces itself).
private struct ThemePreviewCard: View {
    let themeID: NotchThemeID
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var palette: NotchPalette { NotchPalette.for(themeID) }

    private var idleLabel: String {
        // Theme-flavored labels, mirroring the state text from the Claude
        // Design reference (themes.jsx per-state `label`). Feels alive
        // rather than every card just saying "空闲".
        switch themeID {
        case .classic:      return L10n.isChinese ? "空闲" : "Idle"
        case .forest:       return L10n.isChinese ? "空闲" : "Idle"
        case .neonTokyo:    return "IDLE_"
        case .sunset:       return L10n.isChinese ? "静候" : "At rest"
        case .retroArcade:  return "IDLE"
        case .highContrast: return L10n.isChinese ? "空闲" : "Idle"
        case .sakura:       return L10n.isChinese ? "小憩" : "Resting"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Mini pill preview — rounded capsule with the theme's bg,
                // accent dot, a secondary status dot, status label, and
                // "×1" badge. Same layout as the real notch's left wing
                // at closed-state idle.
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    palette.fg.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        )

                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(palette.fg.opacity(0.82))
                            .frame(width: 8, height: 8)
                        Text(idleLabel)
                            .font(.system(
                                size: themeID == .retroArcade ? 9 : 10,
                                weight: themeID == .retroArcade ? .bold : .medium,
                                design: .monospaced
                            ))
                            .foregroundColor(palette.fg)
                            .lineLimit(1)
                            .textCase(themeID == .retroArcade ? .uppercase : nil)
                        Spacer(minLength: 4)
                        Text("×1")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(palette.secondaryFg)
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 28)

                Text(L10n.notchThemeName(themeID))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.72))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? palette.accent.opacity(0.10)
                          : (isHovered
                             ? Color.white.opacity(0.05)
                             : Color.white.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? palette.accent : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(L10n.notchThemeName(themeID)) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

