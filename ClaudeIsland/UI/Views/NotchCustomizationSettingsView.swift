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
            themeRow
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

    // MARK: - Theme picker row

    private var themeRow: some View {
        controlRow(icon: "paintpalette", label: L10n.notchTheme) {
            Menu {
                ForEach(NotchThemeID.allCases) { id in
                    Button {
                        store.update { $0.theme = id }
                    } label: {
                        Label {
                            Text(L10n.notchThemeName(id))
                        } icon: {
                            Circle().fill(NotchPalette.for(id).bg)
                        }
                        .accessibilityLabel("\(L10n.notchThemeName(id)) theme")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(NotchPalette.for(store.customization.theme).bg)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(L10n.notchThemeName(store.customization.theme))
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
            .accessibilityLabel(L10n.notchTheme)
        }
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
