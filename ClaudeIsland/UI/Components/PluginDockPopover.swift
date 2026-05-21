//
//  PluginDockPopover.swift
//  ClaudeIsland
//
//  The header "..." button opens this view. Replaces the older single-list
//  popover with a two-section layout from the Plugin Pinning UI design:
//
//    1. Top: 4 explicit Dock slots (filled = pinned plugin, empty = dashed
//       placeholder). Hovering a filled slot reveals a × unpin button.
//       Slots accept drops from the list below or from each other.
//    2. Bottom: full plugin list. Each row shows a `+ 添加` chip on hover
//       (pinning to the next free slot), a green `DOCK 0n` chip when
//       already pinned, or a gray `已满` chip when the Dock is full.
//
//  Counter chip in the header turns amber when full. Footer link drops
//  to Settings → Plugins.
//
//  All state changes go through `NativePluginManager.{pin,unpin,
//  movePinned}` so persistence, max-cap, and uninstall hooks stay in
//  one place.
//

import SwiftUI

// Drag/drop wiring uses SwiftUI's modern Transferable API
// (.draggable + .dropDestination, macOS 13+). String conforms to
// Transferable by default, so we send the plugin id as a plain
// String payload — no UTI registration / NSItemProvider plumbing
// needed. The old .onDrag/.onDrop pair silently dropped events on
// macOS because NSItemProvider(object: NSString) registered as
// "public.utf8-plain-text" but the .onDrop filter (UTType.plainText
// = "public.plain-text") didn't match through SwiftUI's binding.

extension Color {
    /// Unified accent color for everything plugin-management. Mirrors
    /// the settings gear icon's hover color (#CAFF00) so the header
    /// chrome — pinned plugin icons, the "..." button, and the Dock
    /// popover — all read as one visual family.
    static let pluginAccent = Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)
}

struct PluginDockPopover: View {
    let viewModel: NotchViewModel
    let onClose: () -> Void

    @ObservedObject private var manager = NativePluginManager.shared
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared

    @State private var hoveringRowId: String? = nil
    @State private var hoveringSlotIdx: Int? = nil

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    private var pinnedPlugins: [NativePluginManager.LoadedPlugin?] {
        let loaded = manager.loadedPlugins
        return (0..<NativePluginManager.maxPinned).map { i in
            guard i < manager.pinnedIds.count else { return nil }
            return loaded.first(where: { $0.id == manager.pinnedIds[i] })
        }
    }

    private var atLimit: Bool { manager.pinnedIds.count >= NativePluginManager.maxPinned }

    var body: some View {
        VStack(spacing: 0) {
            header
            slotsRow
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            Divider().background(theme.border.opacity(0.6)).padding(.horizontal, 14)
            listHeader
            pluginList
            footer
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.overlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("顶栏 Dock")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.primaryText)
                Text("拖动调整 · 最多 \(NativePluginManager.maxPinned) 个")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.mutedText)
            }
            Spacer()
            PinCounterChip(count: manager.pinnedIds.count, max: NativePluginManager.maxPinned)
            CloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Slots

    private var slotsRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<NativePluginManager.maxPinned, id: \.self) { idx in
                DockSlot(
                    index: idx,
                    plugin: pinnedPlugins[idx],
                    isDropTarget: hoveringSlotIdx == idx,
                    theme: theme,
                    onDropId: { id in handleDrop(id: id, slotIdx: idx) },
                    onUnpin: {
                        if let p = pinnedPlugins[idx] {
                            withAnimation(.easeOut(duration: 0.18)) {
                                manager.unpin(p.id)
                            }
                        }
                    },
                    hoveringSlotIdx: $hoveringSlotIdx
                )
            }
        }
    }

    // MARK: - List

    private var listHeader: some View {
        HStack {
            Text("全部插件 · \(manager.loadedPlugins.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(theme.secondaryText)
                .tracking(1)
                .textCase(.uppercase)
            Spacer()
            if atLimit {
                Text("● 已满 · 移除一个再添加")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(red: 245/255, green: 176/255, blue: 66/255))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var pluginList: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(manager.loadedPlugins) { plugin in
                    PluginDockRow(
                        plugin: plugin,
                        isPinned: manager.isPinned(plugin.id),
                        slotIndex: manager.pinnedIds.firstIndex(of: plugin.id),
                        atLimit: atLimit,
                        hoveringRowId: $hoveringRowId,
                        theme: theme,
                        onTap: {
                            if manager.isPinned(plugin.id) {
                                // Already in the Dock — single tap launches
                                // the plugin panel (the row's DOCK 0n badge
                                // already tells the user it's pinned).
                                onClose()
                                viewModel.showPlugin(plugin.id)
                            } else if !atLimit {
                                // Free slot available — pin it.
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                    manager.pin(plugin.id)
                                }
                            }
                            // else: at limit + not pinned → no-op (the row
                            //       is already dimmed with "已满").
                        }
                    )
                }
            }
            .padding(.bottom, 6)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("拖到上方槽位 · 点击「+」添加")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.mutedText.opacity(0.7))
            Spacer()
            Button {
                onClose()
                SystemSettingsWindow.shared.show(initialTab: .plugins)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("管理")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(theme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(theme.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Drop dispatch

    /// Drop a dragged plugin id onto slot index `slotIdx`. Routes to
    /// `pin` (new) or `movePinned` (reorder) on the manager.
    private func handleDrop(id: String, slotIdx: Int) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            manager.movePinned(id: id, toSlot: slotIdx)
        }
        hoveringSlotIdx = nil
    }
}

// MARK: - Close button

private struct CloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isHovered ? .white : Color.white.opacity(0.55))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isHovered
                            ? Color(red: 1, green: 0.43, blue: 0.43).opacity(0.85)
                            : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - Pin counter chip

private struct PinCounterChip: View {
    let count: Int
    let max: Int
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared
    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    private var full: Bool { count >= max }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(count)/\(max)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(full ? .orange : Color.pluginAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((full ? Color.orange : Color.pluginAccent).opacity(0.12))
        )
        .overlay(
            Capsule().stroke((full ? Color.orange : Color.pluginAccent).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Dock slot

private struct DockSlot: View {
    let index: Int
    let plugin: NativePluginManager.LoadedPlugin?
    let isDropTarget: Bool
    let theme: ThemeResolver
    let onDropId: (String) -> Void
    let onUnpin: () -> Void

    @Binding var hoveringSlotIdx: Int?

    @State private var hoverX = false

    private var filled: Bool { plugin != nil }

    var body: some View {
        ZStack {
            background

            if let plugin {
                filledContent(plugin)
            } else {
                emptyContent
            }

            slotIndexLabel
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .dropDestination(for: String.self) { items, _ in
            // Modern Transferable-based drop. items contains decoded
            // String payloads — for our plugin reorder use case there's
            // exactly one. Side-step the macOS NSItemProvider UTI-match
            // gotcha that plagued the legacy .onDrop path.
            guard let id = items.first else { return false }
            onDropId(id)
            return true
        } isTargeted: { isHovering in
            if isHovering { hoveringSlotIdx = index }
            else if hoveringSlotIdx == index { hoveringSlotIdx = nil }
        }
        .if(filled) { view in
            view.draggable(plugin?.id ?? "")
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(filled
                ? LinearGradient(
                    colors: [Color.pluginAccent.opacity(0.07), Color.pluginAccent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom)
                : LinearGradient(
                    colors: [Color.white.opacity(0.015), Color.white.opacity(0.015)],
                    startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isDropTarget ? Color.pluginAccent :
                            (filled ? Color.pluginAccent.opacity(0.22) : Color.white.opacity(0.10)),
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            lineCap: .round,
                            dash: filled ? [] : [4, 3])
                    )
            )
    }

    private var slotIndexLabel: some View {
        VStack {
            HStack {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(filled ? Color.pluginAccent.opacity(0.6) : theme.mutedText.opacity(0.6))
                    .padding(.leading, 7)
                    .padding(.top, 5)
                Spacer()
                if filled {
                    unpinButton
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }
            Spacer()
        }
    }

    private var unpinButton: some View {
        Button(action: onUnpin) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(hoverX ? Color(red: 1, green: 0.54, blue: 0.54) : theme.mutedText)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hoverX
                            ? Color(red: 1, green: 0.43, blue: 0.43).opacity(0.18)
                            : Color.black.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .opacity(hoverX || isDropTarget ? 1 : 0.4)
        .onHover { hoverX = $0 }
    }

    private func filledContent(_ plugin: NativePluginManager.LoadedPlugin) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(theme.overlay)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.border, lineWidth: 1)
                    )
                Image(systemName: plugin.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.primaryText)
            }
            .frame(width: 28, height: 28)

            Text(plugin.name)
                .font(.system(size: 10))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isDropTarget ? Color.pluginAccent : theme.mutedText.opacity(0.6))
            Text(isDropTarget ? "松开 →" : "空槽位")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundColor(isDropTarget ? Color.pluginAccent : theme.mutedText.opacity(0.6))
        }
    }
}

// MARK: - List row

private struct PluginDockRow: View {
    let plugin: NativePluginManager.LoadedPlugin
    let isPinned: Bool
    let slotIndex: Int?
    let atLimit: Bool

    @Binding var hoveringRowId: String?

    let theme: ThemeResolver

    let onTap: () -> Void

    private var canPin: Bool { isPinned || !atLimit }
    private var hovered: Bool { hoveringRowId == plugin.id }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(hovered ? Color.pluginAccent.opacity(0.08) : Color.clear)

            HStack(spacing: 10) {
                iconBadge
                VStack(alignment: .leading, spacing: 1) {
                    Text(plugin.name)
                        .font(.system(size: 13))
                        .foregroundColor(theme.primaryText)
                        .lineLimit(1)
                    Text("v\(plugin.version)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(theme.mutedText.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailingChip
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .opacity(canPin || isPinned ? 1.0 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            hoveringRowId = hovering ? plugin.id : (hoveringRowId == plugin.id ? nil : hoveringRowId)
            if hovering && (canPin || isPinned) {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .if(!isPinned && canPin) { view in
            // Only allow drag from list rows that can actually be pinned —
            // matches the "已满" dim state on the row. Already-pinned rows
            // are reordered via the dock slot drag handler, not from here.
            view.draggable(plugin.id)
        }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isPinned ? Color.pluginAccent.opacity(0.08) : theme.overlay)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isPinned ? Color.pluginAccent.opacity(0.18) : theme.border, lineWidth: 1)
                )
            Image(systemName: plugin.icon)
                .font(.system(size: 12))
                .foregroundColor(isPinned ? Color.pluginAccent : theme.primaryText)
        }
        .frame(width: 26, height: 26)
    }

    @ViewBuilder
    private var trailingChip: some View {
        if isPinned, let idx = slotIndex {
            Text("DOCK \(String(format: "%02d", idx + 1))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(Color.pluginAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.pluginAccent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.pluginAccent.opacity(0.22), lineWidth: 1)
                )
        } else if canPin {
            HStack(spacing: 4) {
                Image(systemName: "pin")
                    .font(.system(size: 9))
                Text("添加")
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(hovered ? Color.pluginAccent : theme.mutedText.opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovered ? Color.pluginAccent.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(hovered ? Color.pluginAccent.opacity(0.20) : Color.clear, lineWidth: 1)
            )
        } else {
            Text("已满")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.mutedText.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
        }
    }
}

// MARK: - View+if helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - PluginDockWindow

/// Independent NSPanel window for the Dock UI. Mirrors the
/// `SystemSettingsWindow.shared` pattern: borderless, non-activating,
/// click-outside-to-dismiss. Decouples the Dock from the notch panel's
/// lifecycle entirely — closes don't propagate up, panel auto-collapse
/// timers don't yank it away.
///
/// Why this exists: SwiftUI `.popover()` attached to the notch panel
/// kept dying because three independent close paths (mouse-leave timer,
/// outside-click handler with a CGEvent repost, hover region change)
/// each triggered a panel close that took the popover with it.
@MainActor
final class PluginDockWindow {
    static let shared = PluginDockWindow()

    private var panel: NSPanel?
    private var globalMonitor: Any?

    func show(viewModel: NotchViewModel) {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let dockView = PluginDockPopover(
            viewModel: viewModel,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: dockView)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true

        // .nonactivatingPanel means clicking the panel doesn't yank focus
        // away from whatever app is active — same trick popovers use.
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = hosting
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // CRITICAL: keep this `false`. `isMovableByWindowBackground = true`
        // makes macOS intercept mouse-down on any "background" content as
        // a window-drag, before SwiftUI's hit-test runs — which kills the
        // dock slots' `.draggable` modifiers. Symptom: trying to reorder
        // a pinned plugin instead drags the whole popover around the screen.
        // The popover is anchored top-right, users don't need to move it.
        p.isMovableByWindowBackground = false

        // Anchor near the top-right under the menu bar — that's where
        // the user's "..." button sits. 14pt right inset matches the
        // notch panel's trailing edge convention.
        if let screen = NSScreen.main {
            let f = screen.frame
            let panelW: CGFloat = 340
            let x = f.maxX - panelW - 14
            let y = f.maxY - 480 - 36   // 36 ≈ menu bar (24) + small gap
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.makeKeyAndOrderFront(nil)
        self.panel = p

        installOutsideClickMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
    }

    /// Closes the dock when the user clicks anywhere outside it. Mirrors
    /// the `.transient` behaviour SwiftUI popovers used to give us, but
    /// without the panel-collapse coupling.
    private func installOutsideClickMonitor() {
        if globalMonitor != nil { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // Global monitor fires only for events outside this app's
            // windows — exactly the dismiss trigger we want.
            Task { @MainActor in self?.close() }
        }
    }
}
