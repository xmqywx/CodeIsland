//
//  SSHTunnelManager.swift
//  ClaudeIsland
//
//  Manages SSH reverse tunnel processes for remote relay connections.
//  Spawns, monitors, and auto-restarts ssh -R processes.
//

import Combine
import Foundation
import os.log

/// Manages SSH reverse tunnel processes for each registered host
actor SSHTunnelManager {
    static let shared = SSHTunnelManager()

    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "SSHTunnel")

    // MARK: - State

    /// Active tunnel processes keyed by host UUID
    private var tunnels: [UUID: TunnelProcess] = [:]

    /// Backoff state per host
    private var backoff: [UUID: Int] = [:]

    /// Hosts that were intentionally stopped (should NOT auto-restart)
    private var stoppingHostIds: Set<UUID> = []

    private let maxBackoffSeconds = 60

    // MARK: - Published State

    private nonisolated(unsafe) let stateSubject = CurrentValueSubject<[UUID: SSHConnectionState], Never>([:])

    nonisolated var statePublisher: AnyPublisher<[UUID: SSHConnectionState], Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Tunnel Lifecycle

    /// Start a tunnel for the given host
    func startTunnel(for host: SSHHost) {
        if let existing = tunnels[host.id], existing.process.isRunning {
            Self.logger.info("Tunnel for \(host.host) already running")
            return
        }

        var args = [
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=15",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            "-n",
            "-N",
            "-R", "\(host.localPort):localhost:\(host.localPort)"
        ]

        if let keyPath = host.sshKeyPath {
            args += ["-i", keyPath]
        }

        if host.port != 22 {
            args += ["-p", "\(host.port)"]
        }

        args += ["\(host.user)@\(host.host)"]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = args

        // Capture stderr for debugging
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        do {
            try proc.run()
            Self.logger.info("Started tunnel for \(host.host) on port \(host.localPort)")
        } catch {
            Self.logger.error("Failed to start tunnel for \(host.host): \(error.localizedDescription)")
            updateState(hostId: host.id, state: .disconnected)
            return
        }

        let tunnel = TunnelProcess(process: proc, hostId: host.id)
        tunnels[host.id] = tunnel
        backoff[host.id] = 1
        updateState(hostId: host.id, state: .connected)

        // Monitor process exit
        Task {
            await monitorProcess(tunnel: tunnel, host: host)
        }

        // Log stderr in background
        let tunnelHostId = host.id
        Task.detached { [tunnelHostId] in
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                Self.logger.warning("ssh stderr for \(tunnelHostId): \(str.prefix(200), privacy: .public)")
            }
        }
    }

    /// Stop the tunnel for the given host
    func stopTunnel(for hostId: UUID) {
        guard let tunnel = tunnels[hostId] else { return }
        stoppingHostIds.insert(hostId)
        tunnel.process.terminate()
        tunnels.removeValue(forKey: hostId)
        backoff.removeValue(forKey: hostId)
        updateState(hostId: hostId, state: .disconnected)
        Self.logger.info("Stopped tunnel for \(hostId)")
    }

    /// Stop all tunnels
    func stopAll() {
        for (id, tunnel) in tunnels {
            tunnel.process.terminate()
            tunnels.removeValue(forKey: id)
        }
        backoff.removeAll()
        stateSubject.send([:])
    }

    /// Check if tunnel is running for host
    func isRunning(hostId: UUID) -> Bool {
        return tunnels[hostId]?.process.isRunning ?? false
    }

    // MARK: - Process Monitoring

    private func monitorProcess(tunnel: TunnelProcess, host: SSHHost) {
        tunnel.process.waitUntilExit()

        let exitCode = tunnel.process.terminationStatus
        Self.logger.warning("Tunnel for \(host.host) exited with code \(exitCode)")

        tunnels.removeValue(forKey: host.id)

        // Always clear the stopping flag when the process exits, regardless of reason.
        // The flag only prevents reconnect for the specific stop that set it.
        let wasIntentionalStop = stoppingHostIds.remove(host.id) != nil

        // Skip restart if this was an intentional stop
        if wasIntentionalStop {
            updateState(hostId: host.id, state: .disconnected)
            Self.logger.info("Tunnel for \(host.host) was intentionally stopped, not restarting")
            return
        }

        updateState(hostId: host.id, state: .reconnecting)

        // Auto-restart with backoff
        let delay = min(self.backoff[host.id] ?? 1, maxBackoffSeconds)
        self.backoff[host.id] = (self.backoff[host.id] ?? 1) * 2

        Self.logger.info("Restarting tunnel for \(host.host) in \(delay)s (attempt \(self.backoff[host.id] ?? 1))")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            await self.startTunnel(for: host)
        }
    }

    // MARK: - State Publishing

    private func updateState(hostId: UUID, state: SSHConnectionState) {
        var current = stateSubject.value
        current[hostId] = state
        stateSubject.send(current)

        // Also update registry
        Task {
            await SSHHostRegistry.shared.updateConnectionState(hostId: hostId, state: state)
        }
    }
}

// MARK: - TunnelProcess

private struct TunnelProcess {
    let process: Process
    let hostId: UUID
}
