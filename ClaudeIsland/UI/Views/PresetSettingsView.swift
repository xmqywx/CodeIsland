//
//  PresetSettingsView.swift
//  ClaudeIsland
//
//  Manage launch presets — the named cmux command templates that paired
//  iPhones can trigger remotely. Floating window opened from the notch menu.
//

import SwiftUI

// MARK: - Menu Row (inside NotchMenuView)

struct PresetSettingsRow: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            PresetSettingsWindow.shared.show()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12))
                    .opacity(isHovered ? 1 : 0.6)
                    .frame(width: 16)

                Text("Launch Presets")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(isHovered ? 1 : 0.7)

                Spacer()

                Text("\(PresetStore.shared.presets.count)")
                    .font(.system(size: 10))
                    .opacity(0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

@MainActor
final class PresetSettingsWindow {
    static let shared = PresetSettingsWindow()

    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = PresetSettingsContentView { self.close() }
        let hostingView = NSHostingView(rootView: contentView)
        let windowWidth: CGFloat = 460
        let windowHeight: CGFloat = 520
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.contentView = hostingView

        if let screen = NSScreen.main {
            let f = screen.frame
            w.setFrameOrigin(NSPoint(x: f.midX - windowWidth / 2, y: f.midY - windowHeight / 2))
        }

        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false
        self.window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Content View

private struct PresetSettingsContentView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Launch Presets")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            Divider().background(Color.white.opacity(0.1))
            PresetsListContent(textStyle: .darkOnLight(false))
        }
        .frame(width: 460, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Reusable Presets List

/// Scrollable presets list + add button + edit sheets. Used inside both
/// the legacy PresetSettingsWindow popup (dark-on-dark) and the new
/// SystemSettings "Launch Presets" tab (dark-on-lime). `textStyle` lets
/// the embedder pick foreground colors that work with their background.
struct PresetsListContent: View {
    enum TextStyle {
        case darkOnLight(Bool)  // true → black text (lime bg), false → white text (dark bg)
    }
    let textStyle: TextStyle

    @ObservedObject private var store = PresetStore.shared
    @State private var editing: LaunchPreset?
    @State private var showingNew = false

    private var isLight: Bool {
        if case .darkOnLight(true) = textStyle { return true }
        return false
    }
    private var primaryColor: Color { isLight ? .black : .white }

    var body: some View {
        VStack(spacing: 0) {
            // Hint + Add button row
            HStack {
                Text(L10n.presetsHint)
                    .font(.system(size: 11))
                    .foregroundColor(primaryColor.opacity(0.6))
                Spacer()
                Button {
                    showingNew = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13))
                        Text(L10n.addPreset)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(primaryColor.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(primaryColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Preset list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.presets) { preset in
                        PresetRow(
                            preset: preset,
                            primaryColor: primaryColor,
                            onEdit: { editing = preset },
                            onDelete: { store.delete(id: preset.id) }
                        )
                    }
                    if store.presets.isEmpty {
                        Text(L10n.noPresets)
                            .font(.system(size: 12))
                            .foregroundColor(primaryColor.opacity(0.5))
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .sheet(item: $editing) { preset in
            PresetEditorSheet(preset: preset, isNew: false) { updated in
                store.update(updated)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
        .sheet(isPresented: $showingNew) {
            PresetEditorSheet(
                preset: LaunchPreset(name: "", command: "", icon: "sparkles"),
                isNew: true
            ) { created in
                store.add(created)
                showingNew = false
            } onCancel: {
                showingNew = false
            }
        }
    }
}

private struct PresetRow: View {
    let preset: LaunchPreset
    var primaryColor: Color = .white
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.icon ?? "terminal")
                .font(.system(size: 14))
                .foregroundColor(primaryColor.opacity(0.7))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(primaryColor.opacity(0.9))
                Text(preset.command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(primaryColor.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(primaryColor.opacity(0.55))
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.75, green: 0.15, blue: 0.15))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(primaryColor.opacity(0.08))
        )
    }
}

private struct PresetEditorSheet: View {
    @State var preset: LaunchPreset
    let isNew: Bool
    let onSave: (LaunchPreset) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Preset" : "Edit Preset")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("Claude (skip perms)", text: $preset.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("claude --dangerously-skip-permissions", text: $preset.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Icon (SF Symbol name)").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("sparkles", text: Binding(
                    get: { preset.icon ?? "" },
                    set: { preset.icon = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isNew ? "Add" : "Save") {
                    onSave(preset)
                }
                .keyboardShortcut(.return)
                .disabled(preset.name.isEmpty || preset.command.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
