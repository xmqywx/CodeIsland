//
//  PairPhoneView.swift
//  ClaudeIsland
//
//  QR code pairing button in settings menu + floating QR window.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Menu Row (inside NotchMenuView)

struct PairPhoneRow: View {
    @ObservedObject var syncManager = SyncManager.shared
    @State private var isHovered = false

    var body: some View {
        Button {
            QRPairingWindow.shared.show()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .opacity(isHovered ? 1 : 0.6)
                    .frame(width: 16)

                Text("Pair iPhone")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(isHovered ? 1 : 0.7)

                Spacer()

                if syncManager.isEnabled {
                    HStack(spacing: 3) {
                        Circle().fill(NotchMenuView.brandLime).frame(width: 5, height: 5)
                        Text("Online")
                            .font(.system(size: 9))
                            .foregroundColor(NotchMenuView.brandLime.opacity(0.85))
                    }
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 11))
                        .opacity(0.3)
                }
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

// MARK: - Key-capable borderless window

/// A borderless NSWindow that can still become key, allowing
/// TextField / text input to receive keyboard focus.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Floating QR Window

@MainActor
final class QRPairingWindow {
    static let shared = QRPairingWindow()

    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = QRPairingContentView {
            self.close()
        }

        let hostingView = NSHostingView(rootView: contentView)
        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 560
        let w = KeyableWindow(
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

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.midY - windowHeight / 2
            w.setFrameOrigin(NSPoint(x: x, y: y))
        }

        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false

        // Close on click outside
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak w] event in
            if let window = w, !NSPointInRect(event.locationInWindow, window.contentView?.bounds ?? .zero) {
                if event.window != window {
                    self.close()
                }
            }
            return event
        }

        self.window = w
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - QR Content View

private struct QRPairingContentView: View {
    let onClose: () -> Void
    @ObservedObject private var syncManager = SyncManager.shared
    @State private var qrImage: NSImage?
    @State private var deviceName = Host.current().localizedName ?? "Mac"
    @State private var isHoveringClose = false
    @State private var serverDraft = ""
    @State private var isSavingServer = false
    /// When true, force the "enter server URL" form even though a URL is
    /// already configured — user tapped the edit action to change it.
    @State private var isEditingServer = false
    @State private var linkedDevices: [ServerConnection.LinkedDeviceInfo] = []
    @State private var isUnlinking: String? = nil

    /// Solid brand fill for the popup card — bold, opaque, always readable.
    /// Replaces the old ultraThinMaterial which was so transparent the
    /// window was literally hard to locate against a similar background.
    private static let cardFill = Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)
    /// Near-black text that reads comfortably on the lime card.
    private static let cardText = Color.black

    private var serverUrl: String? {
        let value = SyncManager.shared.serverUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    private var shortCode: String? {
        syncManager.shortCode
    }

    var body: some View {
        VStack(spacing: 14) {
            // Close button
            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Self.cardText.opacity(isHoveringClose ? 0.8 : 0.5))
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
            }
            .padding(.bottom, -8)

            if let url = serverUrl, !isEditingServer {
                pairingContent(serverUrl: url)
            } else {
                notConfiguredContent
            }
        }
        .padding(20)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Self.cardFill)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Self.cardText.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            generateQRCode()
            Task { await refreshLinkedDevices() }
        }
        .onChange(of: shortCode) { _, _ in
            generateQRCode()
        }
    }

    // MARK: - Content subviews

    /// Normal paired state: QR, short code, info pills.
    @ViewBuilder
    private func pairingContent(serverUrl: String) -> some View {
        // QR Code — keep a white card background so the generated black
        // pixels stay crisp and scannable against the lime background.
        if let qrImage {
            Image(nsImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                )
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Self.cardText.opacity(0.08))
                .frame(width: 184, height: 184)
                .overlay(ProgressView().tint(Self.cardText.opacity(0.45)))
        }

        // "Scan or enter code"
        Text("Scan or enter code")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Self.cardText.opacity(0.6))

        // Big short code display
        Text(shortCode ?? "------")
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .tracking(4)
            .foregroundColor(Self.cardText.opacity(shortCode == nil ? 0.3 : 0.95))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Self.cardText.opacity(0.08))
            )

        // Info pills — the server pill is clickable to edit.
        HStack(spacing: 8) {
            Button {
                serverDraft = serverUrl
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditingServer = true
                }
            } label: {
                infoPillContent(
                    icon: "link",
                    text: URL(string: serverUrl)?.host ?? serverUrl,
                    trailing: "pencil"
                )
            }
            .buttonStyle(.plain)
            .help("Change server URL")

            infoPillContent(icon: "desktopcomputer", text: deviceName)
        }

        // Linked devices section
        if !linkedDevices.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Linked Devices")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Self.cardText.opacity(0.6))
                    Spacer()
                    Text("\(linkedDevices.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Self.cardText.opacity(0.5))
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

                ForEach(linkedDevices) { device in
                    HStack(spacing: 6) {
                        Image(systemName: device.kind == "iphone" ? "iphone" : "desktopcomputer")
                            .font(.system(size: 10))
                            .foregroundColor(Self.cardText.opacity(0.7))
                        Text(device.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Self.cardText.opacity(0.9))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            Task { await unlinkDevice(device) }
                        } label: {
                            if isUnlinking == device.id {
                                ProgressView().controlSize(.small).scaleEffect(0.6)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Self.cardText.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isUnlinking != nil)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Self.cardText.opacity(0.06))
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    /// Empty state (or edit mode) — lets the user type a server URL inline
    /// and save it. No separate Settings window needed.
    @ViewBuilder
    private var notConfiguredContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Self.cardText.opacity(0.55))

            VStack(spacing: 4) {
                Text(isEditingServer ? "Change Server" : "CodeLight Server")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Self.cardText.opacity(0.95))
                Text(isEditingServer
                     ? "Enter a new server URL. The current Mac will reconnect after saving."
                     : "Enter your self-hosted server URL to start pairing.")
                    .font(.system(size: 11))
                    .foregroundColor(Self.cardText.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            TextField("https://your-server.example", text: $serverDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Self.cardText.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Self.cardText.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Self.cardText.opacity(0.25), lineWidth: 0.5)
                )
                .padding(.horizontal, 4)
                .disabled(isSavingServer)

            HStack(spacing: 8) {
                if isEditingServer {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditingServer = false
                            serverDraft = ""
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Self.cardText.opacity(0.08))
                            )
                            .foregroundColor(Self.cardText.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Self.cardText.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    saveServerURL()
                } label: {
                    HStack(spacing: 6) {
                        if isSavingServer {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        }
                        Text(isSavingServer ? "Connecting…" : (isEditingServer ? "Save" : "Save and Connect"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isValidDraft ? Self.cardText.opacity(0.9) : Self.cardText.opacity(0.15))
                    )
                    .foregroundColor(isValidDraft ? Self.cardFill : Self.cardText.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!isValidDraft || isSavingServer)
            }
            .padding(.horizontal, 4)

            Text("This URL is stored locally. It never leaves your Mac.")
                .font(.system(size: 10))
                .foregroundColor(Self.cardText.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    private var isValidDraft: Bool {
        let s = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let u = URL(string: s), let scheme = u.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && (u.host?.isEmpty == false)
    }

    private func saveServerURL() {
        let s = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDraft else { return }
        isSavingServer = true
        SyncManager.shared.serverUrl = s
        // SyncManager.serverUrl didSet triggers connectToServer automatically,
        // which populates shortCode + flips isEnabled. The view will re-render
        // into pairingContent as soon as syncManager publishes the change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSavingServer = false
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditingServer = false
            }
            serverDraft = ""
        }
    }

    /// Info pill rendered in dark-on-lime style, with optional trailing icon
    /// (used by the server pill to hint it's editable).
    private func infoPillContent(icon: String, text: String, trailing: String? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9))
                .lineLimit(1)
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 7))
                    .opacity(0.8)
            }
        }
        .foregroundColor(Self.cardText.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Self.cardText.opacity(0.1)))
    }

    private func refreshLinkedDevices() async {
        guard let conn = SyncManager.shared.connection else { return }
        linkedDevices = await conn.fetchLinkedDevices()
    }

    private func unlinkDevice(_ device: ServerConnection.LinkedDeviceInfo) async {
        guard let conn = SyncManager.shared.connection else { return }
        isUnlinking = device.id
        do {
            try await conn.unlinkDevice(device.id)
            linkedDevices.removeAll { $0.id == device.id }
        } catch {
            // Silently ignore — device might already be unlinked
        }
        isUnlinking = nil
    }

    private func generateQRCode() {
        // No point generating a QR when the host isn't set — the pairing
        // screen already tells the user to configure one in Settings.
        guard let url = serverUrl else {
            qrImage = nil
            return
        }
        // New payload format: {server, code}. iPhone parses these and calls
        // POST /v1/pairing/code/redeem.
        let payload: [String: String] = [
            "server": url,
            "code": shortCode ?? "",
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return }

        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return }

        qrImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
