//
//  SSHHostsView.swift
//  ClaudeIsland
//
//  SSH host management for remote session monitoring.
//  Uses the same floating-window pattern as PresetSettingsView.
//

import AppKit
import Combine
import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.codeisland", category: "SSHHosts")

// MARK: - Menu Row (inside NotchMenuView)

struct SSHHostsRow: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            SSHHostsWindow.shared.show()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isHovered ? 1 : 0.6))
                    .frame(width: 16)

                Text("SSH Hosts")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1 : 0.7))

                Spacer()

                Text("\(SSHHostStore.shared.hosts.count)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
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
final class SSHHostsWindow {
    static let shared = SSHHostsWindow()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SSHHostsContentView { self.close() }
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

// MARK: - Store

@MainActor
final class SSHHostStore: ObservableObject {
    static let shared = SSHHostStore()

    @Published private(set) var hosts: [SSHHost] = []
    @Published private(set) var deployStatus: [UUID: DeployStatus] = [:]

    enum DeployStatus: Equatable {
        case idle
        case deploying
        case success
        case failed(String)

        var errorMessage: String? {
            if case .failed(let msg) = self { return msg }
            return nil
        }
    }

    private init() {
        Task { await refresh() }
    }

    func refresh() async {
        hosts = await SSHHostRegistry.shared.currentHosts()
        logger.info("SSHHostStore refreshed: \(self.hosts.count) hosts")
    }

    func addHost(host: String, user: String, port: Int, sshKeyPath: String?, connectionMode: ConnectionMode) async {
        await SSHHostRegistry.shared.addHost(
            host: host,
            user: user,
            port: port,
            sshKeyPath: sshKeyPath,
            connectionMode: connectionMode
        )
        await refresh()
    }

    func updateHost(_ host: SSHHost) async {
        await SSHHostRegistry.shared.updateHost(host)
        await refresh()
    }

    func removeHost(id: UUID) async {
        await SSHHostRegistry.shared.removeHost(id: id)
        await refresh()
    }

    func deployHost(_ host: SSHHost) {
        deployStatus[host.id] = .deploying
        logger.info("Deploying to \(host.user)@\(host.host): port=\(host.port), localPort=\(host.localPort)")

        // Resolve network params on main actor first (fast), then do SSH/SCP in detached task
        // to avoid blocking the main thread with synchronous process calls.
        Task {
            // Step 1: Get Mac IP (may block briefly but releases main actor during ifconfig)
            guard let macIP = await getMacIP() else {
                logger.error("Cannot deploy: Mac IP not detected")
                deployStatus[host.id] = .failed("Mac IP not detected. Check network.")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { deployStatus[host.id] = .idle }
                return
            }

            // Step 2: Get PSK (fast, synchronous Keychain access)
            let psk = await SSHHostRegistry.shared.getOrCreatePSK()
            logger.info("Using macIP=\(macIP), psk length=\(psk.count)")

            // Step 3: Run all SSH/SCP commands in a detached task so blocking
            // process.waitUntilExit() calls don't freeze the main thread.
            // Race the deployment against a 2-minute timeout as safety net.
            let deployError: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await HookInstaller.deployToSSHHost(
                        host: host,
                        macIP: macIP,
                        psk: psk,
                        sshKeyPath: host.sshKeyPath
                    )
                }

                group.addTask {
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                    return "Deployment timed out after 2 minutes"
                }

                // Return the first result (deployment or timeout)
                let result = await group.next()
                // Cancel remaining tasks
                group.cancelAll()
                return result ?? "Unknown deployment error"
            }

            // Step 4: Update UI on main actor
            if let error = deployError {
                logger.error("Deploy failed: \(error)")
                deployStatus[host.id] = .failed(error)
            } else {
                logger.info("Deploy succeeded")
                deployStatus[host.id] = .success
                // Only start SSH tunnel for tunnel mode; direct mode connects directly
                if host.connectionMode == .sshReverseTunnel {
                    await SSHTunnelManager.shared.startTunnel(for: host)
                }
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { deployStatus[host.id] = .idle }
        }
    }

    func getMacIP() async -> String? {
        // Try en0 first (通常是WiFi), then en1 (以太网), then en2
        for iface in ["en0", "en1", "en2", "en3"] {
            let result = await Task.detached(priority: .utility) { () -> String? in
                let pipe = Pipe()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
                process.arguments = [iface]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        // Look for IPv4 address (inet) - skip loopback (127.0.0.1)
                        let pattern = #"inet (\d+\.\d+\.\d+\.\d+)"#
                        if let regex = try? NSRegularExpression(pattern: pattern),
                           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                           let range = Range(match.range(at: 1), in: output) {
                            let ip = String(output[range])
                            if ip != "127.0.0.1" {
                                return ip
                            }
                        }
                    }
                } catch {
                    return nil
                }
                return nil
            }.value
            if let ip = result {
                return ip
            }
        }
        return nil
    }
}

// MARK: - Content View

private struct SSHHostsContentView: View {
    let onClose: () -> Void
    @ObservedObject private var store = SSHHostStore.shared
    @State private var editingHost: SSHHost?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SSH Hosts")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
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

            Text("Deploy relay scripts to remote Macs to monitor Claude Code sessions")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            // Host list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.hosts) { host in
                        SSHHostRow(
                            host: host,
                            deployStatus: store.deployStatus[host.id] ?? .idle,
                            onEdit: { editingHost = host },
                            onDeploy: { store.deployHost(host) },
                            onDelete: { Task { await store.removeHost(id: host.id) } }
                        )
                    }
                    if store.hosts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "network.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No SSH Hosts")
                                .font(.headline)
                            Text("Add a remote Mac to monitor its Claude Code sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(12)
            }
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
        .sheet(item: $editingHost) { host in
            SSHHostEditorSheet(host: host, isNew: false) { updated in
                Task {
                    await store.updateHost(updated)
                    editingHost = nil
                }
            } onCancel: {
                editingHost = nil
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            SSHHostEditorSheet(
                host: SSHHost(id: UUID(), host: "", user: "", port: 22, localPort: 9871, sshKeyPath: nil, connectionMode: .sshReverseTunnel, connectionState: .disconnected),
                isNew: true
            ) { newHost in
                Task {
                    await store.addHost(host: newHost.host, user: newHost.user, port: newHost.port, sshKeyPath: newHost.sshKeyPath, connectionMode: newHost.connectionMode)
                    showingAddSheet = false
                }
            } onCancel: {
                showingAddSheet = false
            }
        }
    }
}

// MARK: - Host Row

private struct SSHHostRow: View {
    let host: SSHHost
    let deployStatus: SSHHostStore.DeployStatus
    let onEdit: () -> Void
    let onDeploy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Connection state icon
            connectionIcon

            VStack(alignment: .leading, spacing: 2) {
                Text("\(host.user)@\(host.host)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("Local port \(host.localPort)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                if let error = deployStatus.errorMessage {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Deploy button
            Button(action: onDeploy) {
                switch deployStatus {
                case .idle:
                    Text("Deploy")
                        .font(.system(size: 12))
                case .deploying:
                    ProgressView()
                        .controlSize(.small)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.bordered)
            .disabled(deployStatus == .deploying)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch host.connectionState {
        case .connected:
            Image(systemName: "globe")
                .foregroundStyle(.green)
        case .reconnecting:
            Image(systemName: "globe")
                .foregroundStyle(.orange)
        case .disconnected:
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Editor Sheet

private struct SSHHostEditorSheet: View {
    @State var host: SSHHost
    let isNew: Bool
    let onSave: (SSHHost) -> Void
    let onCancel: () -> Void

    @State private var portError: String?
    @State private var keyError: String?

    private var isValid: Bool {
        !host.host.isEmpty && !host.user.isEmpty && portError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add SSH Host" : "Edit SSH Host")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Hostname").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("e.g., lisa.local", text: $host.host)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("User").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("e.g., toby", text: $host.user)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Port").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("22", text: Binding(
                    get: { String(host.port) },
                    set: {
                        host.port = Int($0) ?? 22
                        if Int($0) == nil && !$0.isEmpty {
                            portError = "Enter a valid port number"
                        } else {
                            portError = nil
                        }
                    }
                ))
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                if let error = portError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SSH Key (optional)").font(.system(size: 11)).foregroundColor(.secondary)
                TextField("Leave empty for default (~/.ssh/id_rsa)", text: Binding(
                    get: { host.sshKeyPath ?? "" },
                    set: {
                        host.sshKeyPath = $0.isEmpty ? nil : $0
                        if !$0.isEmpty && !FileManager.default.fileExists(atPath: $0) {
                            keyError = "File not found"
                        } else {
                            keyError = nil
                        }
                    }
                ))
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                if let error = keyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Connection Mode").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("Connection Mode", selection: $host.connectionMode) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(host.connectionMode.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isNew ? "Add" : "Save") {
                    onSave(host)
                }
                .keyboardShortcut(.return)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
