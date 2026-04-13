//
//  SystemSettingsView.swift
//  ClaudeIsland
//
//  Floating "System Settings" window — the single home for every
//  configuration surface that used to crowd the notch menu or open its
//  own one-off popup (Launch Presets included).
//
//  Layout: vertical sidebar on the left (tab list), detail view on the
//  right. Designed to scale to many more tabs as config grows — add
//  a new case to `SettingsTab`, a new content view, and a single line
//  in the dispatcher.
//
//  Theme: solid brand lime (#CAFF00) surface with near-black text,
//  matching the Pair phone QR popup.
//

import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

// MARK: - Notch menu entry row

struct SystemSettingsRow: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            SystemSettingsWindow.shared.show()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .opacity(isHovered ? 1 : 0.6)
                    .frame(width: 16)

                Text(L10n.openSettings)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(isHovered ? 1 : 0.7)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Floating Window

/// Borderless NSWindows return `false` from `canBecomeKey` by default,
/// which blocks SwiftUI TextFields inside them from receiving keyboard
/// focus. Overriding this lets text inputs (e.g. the Anthropic API Proxy
/// field) accept typing. Mirrors the pattern in PairPhoneView.swift.
private final class KeyableSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SystemSettingsWindow {
    static let shared = SystemSettingsWindow()

    private var window: NSWindow?

    func show(initialTab: SettingsTab = .general) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SystemSettingsContentView(initialTab: initialTab) { self.close() }
        let hostingView = NSHostingView(rootView: contentView)
        let w = KeyableSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.contentView = hostingView
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.cornerRadius = 16
        w.contentView?.layer?.masksToBounds = true

        if let screen = NSScreen.main {
            let f = screen.frame
            w.setFrameOrigin(NSPoint(x: f.midX - 360, y: f.midY - 280))
        }

        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        NSApplication.shared.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false
        self.window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Tab enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case notifications
    case behavior
    case plugins
    case codelight       // Pair iPhone + Launch Presets merged
    case cmuxConnection  // diagnostics for phone→terminal relay
    case logs            // live DebugLogger tail
    case advanced
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:        return "gearshape.fill"
        case .appearance:     return "paintbrush.fill"
        case .notifications:  return "bell.badge.fill"
        case .behavior:       return "slider.horizontal.3"
        case .plugins:        return "puzzlepiece.extension.fill"
        case .codelight:      return "iphone.radiowaves.left.and.right"
        case .cmuxConnection: return "terminal.fill"
        case .logs:           return "doc.text.magnifyingglass"
        case .advanced:       return "wrench.and.screwdriver.fill"
        case .about:          return "info.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .general:        return L10n.tabGeneral
        case .appearance:     return L10n.tabAppearance
        case .notifications:  return L10n.tabNotifications
        case .behavior:       return L10n.tabBehavior
        case .plugins:        return "Plugins"
        case .codelight:      return L10n.tabCodeLight
        case .cmuxConnection: return L10n.tabCmuxConnection
        case .logs:           return L10n.tabLogs
        case .advanced:       return L10n.tabAdvanced
        case .about:          return L10n.tabAbout
        }
    }
}

// MARK: - Shared theming constants

/// Two-surface theme: the sidebar is a bold lime strip, the detail area is
/// a dark panel so the content doesn't feel retina-burning. This also
/// matches the existing dark-themed embedded rows (ScreenPickerRow, etc.)
/// without forcing a colorScheme override on them.
private enum Theme {
    // Brand lime — ONLY used on the sidebar surface.
    static let sidebarFill = Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)
    static let sidebarText = Color.black
    static let sidebarSelected = Color.black.opacity(0.85)
    static let sidebarSelectedText = Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)
    static let sidebarBorder = Color.black.opacity(0.12)

    // Dark panel — used for the detail area, cards, toggles, text.
    static let detailFill = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let detailText = Color.white
    static let cardFill = Color.white.opacity(0.04)
    static let cardBorder = Color.white.opacity(0.08)
    static let subtle = Color.white.opacity(0.5)
}

// MARK: - Content root

private struct SystemSettingsContentView: View {
    let initialTab: SettingsTab
    let onClose: () -> Void
    @State private var tab: SettingsTab

    init(initialTab: SettingsTab = .general, onClose: @escaping () -> Void) {
        self.initialTab = initialTab
        self.onClose = onClose
        self._tab = State(initialValue: initialTab)
    }

    var body: some View {
        // IMPORTANT: clipShape BEFORE overlay so the rounded corners actually
        // cut the sidebar's opaque lime fill and the detail's dark fill,
        // then the overlay border is stroked on the clipped edge on top.
        // Putting shadow OUTSIDE the clip so it isn't cut off.
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(width: 720, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.sidebarText.opacity(0.75))
                Text(L10n.systemSettings)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.sidebarText.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // Tab list
            ForEach(SettingsTab.allCases) { t in
                tabRow(t)
            }

            Spacer()

            // Close button at bottom
            Button {
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                    Text(L10n.back)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Theme.sidebarText.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 180)
        .background(Theme.sidebarFill)
    }

    @ViewBuilder
    private func tabRow(_ t: SettingsTab) -> some View {
        let isSelected = tab == t
        Button {
            withAnimation(.easeOut(duration: 0.15)) { tab = t }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: t.icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                Text(t.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(isSelected ? Theme.sidebarSelectedText : Theme.sidebarText.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.sidebarSelected : Color.clear)
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(tab.label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.detailText.opacity(0.95))
                    .padding(.top, 18)

                switch tab {
                case .general:        GeneralTab()
                case .appearance:     AppearanceTab()
                case .notifications:  NotificationsTab()
                case .behavior:       BehaviorTab()
                case .plugins:        NativePluginStoreView()
                case .codelight:      CodeLightTab()
                case .cmuxConnection: CmuxConnectionTab()
                case .logs:           LogsTab()
                case .advanced:       AdvancedTab()
                case .about:          AboutTab()
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.detailFill)
    }
}

// MARK: - Reusable tab-level primitives

/// A bordered card container used by each tab to group related controls.
/// Dark theme: translucent white fill over the detail panel, thin border.
private struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundColor(Theme.subtle)
            }
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                    )
            )
        }
    }
}

/// Dark-themed toggle cell — lime dot when on, matching the sidebar accent.
private struct TabToggle: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isOn ? 0.9 : 0.5))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundColor(.white.opacity(isOn ? 0.95 : 0.7))
                Spacer(minLength: 0)
                Circle()
                    .fill(isOn ? Theme.sidebarFill : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isOn ? Theme.sidebarFill.opacity(0.1) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isOn ? Theme.sidebarFill.opacity(0.25) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @State private var hooksInstalled = HookInstaller.isInstalled()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ObservedObject private var codexGate = CodexFeatureGate.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    TabToggle(icon: "power", label: L10n.launchAtLogin, isOn: launchAtLogin) {
                        do {
                            if launchAtLogin {
                                try SMAppService.mainApp.unregister()
                                launchAtLogin = false
                            } else {
                                try SMAppService.mainApp.register()
                                launchAtLogin = true
                            }
                        } catch {}
                    }
                    TabToggle(icon: "arrow.triangle.2.circlepath", label: L10n.hooks, isOn: hooksInstalled) {
                        if hooksInstalled {
                            HookInstaller.uninstall()
                            hooksInstalled = false
                        } else {
                            HookInstaller.installIfNeeded()
                            hooksInstalled = true
                        }
                    }
                    TabToggle(icon: "terminal.fill", label: L10n.codexSupport, isOn: codexGate.isEnabled) {
                        codexGate.isEnabled.toggle()
                    }
                }
            }

            SettingsCard(title: L10n.anthropicApiProxy) {
                AnthropicProxyRow()
            }

            SettingsCard(title: L10n.language) {
                LanguageRow()
            }

            SettingsCard(title: L10n.accessibility) {
                AccessibilityRow(isEnabled: AXIsProcessTrusted())
            }
        }
    }
}

/// Text field for configuring an HTTP(S) proxy for Anthropic API traffic.
/// See the explanatory Text below for exact scope.
private struct AnthropicProxyRow: View {
    @AppStorage("anthropicProxyURL") private var proxyURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L10n.anthropicApiProxyPlaceholder, text: $proxyURL)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            Text(L10n.anthropicApiProxyDescription)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Appearance tab

private struct AppearanceTab: View {
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @AppStorage("showGroupedSessions") private var showGrouped: Bool = false
    @AppStorage("usePixelCat") private var usePixelCat: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.screen) {
                ScreenPickerRow(screenSelector: screenSelector)
            }

            SettingsCard {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    TabToggle(icon: "cat", label: L10n.pixelCatMode, isOn: usePixelCat) { usePixelCat.toggle() }
                    TabToggle(icon: "folder", label: L10n.groupByProject, isOn: showGrouped) { showGrouped.toggle() }
                }
            }

            // Notch customization — theme, font size, visibility,
            // hardware mode, and the live edit entry button.
            SettingsCard(title: L10n.notchSectionHeader) {
                NotchCustomizationSettingsView()
            }
        }
    }
}

// MARK: - Notifications tab

private struct NotificationsTab: View {
    @ObservedObject private var soundSelector = SoundSelector.shared
    @AppStorage("usageWarningThreshold") private var usageWarningThreshold: Int = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.notificationSound) {
                SoundPickerRow(soundSelector: soundSelector)
            }
            SettingsCard(title: L10n.usageWarningThreshold) {
                ThresholdPickerRow(threshold: $usageWarningThreshold)
            }
        }
    }
}

// MARK: - Behavior tab

private struct BehaviorTab: View {
    @AppStorage("smartSuppression") private var smartSuppression: Bool = true
    @AppStorage("autoCollapseOnMouseLeave") private var autoCollapseOnMouseLeave: Bool = true
    @AppStorage("compactCollapsed") private var compactCollapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    TabToggle(icon: "eye.slash", label: L10n.smartSuppression, isOn: smartSuppression) { smartSuppression.toggle() }
                    TabToggle(icon: "rectangle.compress.vertical", label: L10n.autoCollapseOnMouseLeave, isOn: autoCollapseOnMouseLeave) { autoCollapseOnMouseLeave.toggle() }
                    TabToggle(icon: "rectangle.arrowtriangle.2.inward", label: L10n.compactCollapsed, isOn: compactCollapsed) { compactCollapsed.toggle() }
                }
            }
        }
    }
}

// MARK: - CodeLight tab (Pair iPhone + Launch Presets merged)

private struct CodeLightTab: View {
    @ObservedObject private var syncManager = SyncManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.pairedIPhones) {
                HStack(spacing: 10) {
                    Image(systemName: syncManager.isEnabled
                          ? "iphone.radiowaves.left.and.right"
                          : "iphone.slash")
                        .font(.system(size: 14))
                        .foregroundColor(syncManager.isEnabled
                                         ? Theme.sidebarFill
                                         : Color.white.opacity(0.4))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        if let url = syncManager.serverUrl,
                           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(URL(string: url)?.host ?? url)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Text(syncManager.isEnabled
                                 ? (L10n.isChinese ? "在线" : "Online")
                                 : (L10n.isChinese ? "未连接" : "Not connected"))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        } else {
                            Text(L10n.isChinese ? "尚未配置服务器" : "No server configured")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    Button {
                        QRPairingWindow.shared.show()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 11))
                            Text(L10n.pairNewPhone)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Theme.sidebarFill)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsCard(title: L10n.launchPresetsSection) {
                PresetsListContent(textStyle: .darkOnLight(false))
                    .frame(minHeight: 280)
            }
        }
    }
}

// MARK: - Advanced tab

private struct AdvancedTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.clearEndedSessions) {
                Button {
                    Task { await SessionStore.shared.process(.clearEndedSessions) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text(L10n.clearEnded)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(Theme.detailText.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - About tab

private struct AboutTab: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                HStack {
                    Text(L10n.version)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.detailText.opacity(0.9))
                    Spacer()
                    Text(version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.detailText.opacity(0.6))
                }
            }

            SettingsCard {
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/xmqywx/CodeIsland")!)
                    } label: {
                        aboutLinkButton(icon: "star.fill", label: L10n.starOnGitHub)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/xmqywx/CodeIsland/issues")!)
                    } label: {
                        aboutLinkButton(icon: "bubble.left", label: L10n.feedback)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Plugin marketplace promo card
            SettingsCard {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.pluginMarketplaceTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.detailText.opacity(0.9))
                        Text(L10n.pluginMarketplaceDesc)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.detailText.opacity(0.55))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://miomio.chat/plugins")!)
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.pluginMarketplaceOpen)
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsCard {
                HStack {
                    Image(systemName: "message.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.detailText.opacity(0.6))
                    Text(L10n.wechatLabel)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.detailText.opacity(0.8))
                    Spacer()
                    Text("A115939")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.detailText.opacity(0.55))
                        .textSelection(.enabled)
                }
            }

            Text(L10n.maintainedTagline)
                .font(.system(size: 11))
                .foregroundColor(Theme.detailText.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private func aboutLinkButton(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.sidebarFill)
        )
    }
}

// MARK: - cmux Connection tab

/// Phone → terminal relay diagnostics. Replaces the invisible failure modes
/// that used to leave users with "phone says sent, cmux shows nothing".
private struct CmuxConnectionTab: View {
    @State private var probe: TerminalWriter.ConnectionProbe?
    @State private var isRefreshing = false
    @State private var testState: TestState = .idle
    @State private var testDetail: String = ""
    @State private var automationState: AutomationState = .idle
    @State private var automationDetail: String = ""

    enum TestState { case idle, sending, done }
    enum AutomationState { case idle, requesting, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.cmuxTabHeader)
                .font(.system(size: 11))
                .foregroundColor(Theme.subtle)

            SettingsCard {
                statusRow(
                    icon: "terminal.fill",
                    title: L10n.cmuxBinaryRow,
                    ok: probe?.cmuxBinaryInstalled ?? false,
                    detail: (probe?.cmuxBinaryInstalled ?? false) ? L10n.cmuxBinaryFound : L10n.cmuxBinaryMissing
                )
                statusRow(
                    icon: "accessibility",
                    title: L10n.accessibilityRowTitle,
                    ok: probe?.accessibilityGranted ?? false,
                    detail: (probe?.accessibilityGranted ?? false) ? L10n.accessibilityGranted : L10n.accessibilityDenied
                )
                statusRow(
                    icon: "gearshape.2",
                    title: L10n.automationRowTitle,
                    ok: probe?.automationGranted,
                    detail: probe?.automationDetail ?? L10n.automationUnknown
                )
                statusRow(
                    icon: "person.crop.rectangle.stack",
                    title: L10n.runningClaudeCount,
                    ok: (probe?.claudeSessionCount ?? 0) > 0,
                    detail: "\(probe?.claudeSessionCount ?? 0)"
                )
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Task { await runTest() }
                        } label: {
                            HStack(spacing: 6) {
                                if testState == .sending {
                                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "paperplane.fill").font(.system(size: 11))
                                }
                                Text(testState == .sending ? L10n.testSending : L10n.testSendButton)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.sidebarFill))
                        }
                        .buttonStyle(.plain)
                        .disabled(testState == .sending)

                        Button {
                            Task { await refresh() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 11))
                                Text(L10n.refreshStatus).font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRefreshing)
                    }

                    if testState == .done, !testDetail.isEmpty {
                        Text(testDetail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsCard {
                VStack(spacing: 8) {
                    permissionButton(label: L10n.openAccessibilitySettings, urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    permissionButton(label: L10n.openAutomationSettings, urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")

                    // Proactive Automation-prompt trigger. macOS won't let the
                    // user add an app to the Automation whitelist manually;
                    // tapping this dispatches a no-op `activate` AppleEvent
                    // to the first running terminal, surfacing the TCC dialog.
                    Button {
                        Task { await requestAutomation() }
                    } label: {
                        HStack(spacing: 8) {
                            if automationState == .requesting {
                                ProgressView().scaleEffect(0.5).frame(width: 11, height: 11)
                            } else {
                                Image(systemName: "hand.raised.fill").font(.system(size: 11))
                            }
                            Text(L10n.requestAutomationButton).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9)).opacity(0.4)
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(automationState == .requesting)

                    if automationState == .done, !automationDetail.isEmpty {
                        Text(automationDetail)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .task { await refresh() }
    }

    private func requestAutomation() async {
        automationState = .requesting
        automationDetail = ""
        let (_, detail) = await TerminalWriter.shared.requestAutomationPermission()
        automationDetail = detail
        automationState = .done
    }

    @ViewBuilder
    private func statusRow(icon: String, title: String, ok: Bool?, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Circle()
                .fill(dotColor(ok))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }

    private func dotColor(_ ok: Bool?) -> Color {
        switch ok {
        case .some(true): return Color(red: 0.3, green: 0.85, blue: 0.35)
        case .some(false): return Color(red: 0.95, green: 0.35, blue: 0.35)
        case .none: return Color.white.opacity(0.25)
        }
    }

    private func permissionButton(label: String, urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9)).opacity(0.4)
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        isRefreshing = true
        let p = await TerminalWriter.shared.probeConnection()
        self.probe = p
        isRefreshing = false
    }

    private func runTest() async {
        testState = .sending
        testDetail = ""
        let (ok, detail) = await TerminalWriter.shared.testSendDiagnostic()
        testDetail = detail
        testState = .done
        // Also refresh the status rows while we're at it.
        let p = await TerminalWriter.shared.probeConnection()
        self.probe = p
        _ = ok
    }
}

// MARK: - Logs tab

/// Live tail of ~/.claude/.codeisland.log with issue-submission affordances.
/// Exists to turn "CodeIsland is broken, help" into something users can
/// self-serve into a GitHub issue without scrolling for log files.
private struct LogsTab: View {
    @StateObject private var streamer = LogStreamer.shared
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.logsHeader)
                .font(.system(size: 11))
                .foregroundColor(Theme.subtle)

            HStack(spacing: 8) {
                toolbarButton(icon: "doc.on.doc", label: justCopied ? L10n.logsCopied : L10n.logsCopyAll) {
                    let snapshot = streamer.currentSnapshot()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snapshot, forType: .string)
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        justCopied = false
                    }
                }
                toolbarButton(icon: "folder", label: L10n.logsOpenFile) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: streamer.logFilePath)])
                }
                toolbarButton(icon: "exclamationmark.bubble", label: L10n.logsSubmitIssue) {
                    openIssue()
                }
            }

            SettingsCard {
                logView
            }
        }
        .task {
            streamer.startIfNeeded()
        }
        .onDisappear {
            streamer.stopIfUnused()
        }
    }

    @ViewBuilder
    private var logView: some View {
        if streamer.lines.isEmpty {
            Text(L10n.logsEmpty)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(streamer.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(colorFor(line: line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 320)
                .onChange(of: streamer.lines.count) { _, _ in
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func colorFor(line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") {
            return Color(red: 1.0, green: 0.55, blue: 0.55)
        }
        if lower.contains("warning") || lower.contains("timeout") {
            return Color(red: 1.0, green: 0.85, blue: 0.4)
        }
        return Color.white.opacity(0.8)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func openIssue() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = Foundation.ProcessInfo.processInfo.operatingSystemVersionString

        // 1. Put the FULL log on the clipboard. GitHub's issue-new endpoint
        //    caps prefilled URLs around 8KB — 200 lines URL-encoded blows
        //    past that and the page breaks. Clipboard has no such limit,
        //    so users can paste arbitrarily large logs into the textarea.
        let fullSnapshot = streamer.currentSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullSnapshot, forType: .string)

        // 2. Put a short tail inline in the URL as a preview. A normal line is
        //    ~100 chars, so 20 lines × 3x URL-encoding ≈ 6KB — fits under the
        //    8KB limit. But a single stack trace line can be 500+ chars and
        //    blow the budget with even 10 lines. So we measure the actual
        //    encoded URL length and progressively shrink the tail until it
        //    fits under `maxURLBytes`, falling back to an empty preview if
        //    even 1 line is too fat. The clipboard copy above guarantees the
        //    user can always paste the full log regardless.
        let maxURLBytes = 6000  // conservative — GitHub's hard limit is ~8KB
        var previewLineCount = 20
        var finalURL: URL?
        while previewLineCount >= 0 {
            let tail = previewLineCount > 0
                ? streamer.lines.suffix(previewLineCount).joined(separator: "\n")
                : "(omitted — see clipboard)"

            let body = """
            **Describe the issue**
            <!-- What happened? What did you expect? -->

            **Environment**
            - CodeIsland: \(version) (build \(build))
            - macOS: \(os)

            **Recent logs (preview — last \(previewLineCount) lines)**
            ```
            \(tail)
            ```

            **Full log**
            > \(L10n.logsIssueClipboardNotice)

            ```
            <!-- paste here -->
            ```
            """

            var comps = URLComponents(string: "https://github.com/MioMioOS/MioIsland/issues/new")!
            comps.queryItems = [
                URLQueryItem(name: "title", value: "[Bug] "),
                URLQueryItem(name: "body", value: body)
            ]
            if let candidate = comps.url, candidate.absoluteString.count <= maxURLBytes {
                finalURL = candidate
                break
            }
            // Halve and retry (20 → 10 → 5 → 2 → 1 → 0).
            if previewLineCount == 0 { break }
            previewLineCount = previewLineCount > 1 ? previewLineCount / 2 : 0
        }

        if let url = finalURL {
            NSWorkspace.shared.open(url)
        }
    }
}
