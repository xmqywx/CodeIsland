//
//  ClaudeSessionMonitor.swift
//  ClaudeIsland
//
//  MainActor wrapper around SessionStore for UI binding.
//  Publishes SessionState arrays for SwiftUI observation.
//

import AppKit
import Combine
import Foundation
import os.log

@MainActor
class ClaudeSessionMonitor: ObservableObject {
    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "SessionMonitor")
    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        SessionStore.shared.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateFromSessions(sessions)
            }
            .store(in: &cancellables)

        InterruptWatcherManager.shared.delegate = self
    }

    // MARK: - Monitoring Lifecycle

    func startMonitoring() {
        HookSocketServer.shared.start(
            onEvent: { event in
                Task {
                    await SessionStore.shared.process(.hookReceived(event))
                }

                if event.sessionPhase == .processing {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.startWatching(
                            sessionId: event.sessionId,
                            cwd: event.cwd
                        )
                    }
                }

                if event.status == "ended" {
                    Task { @MainActor in
                        InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                    }
                }

                if event.event == "Stop" {
                    HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                }

                if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                    HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                }
            },
            onPermissionFailure: { sessionId, toolUseId in
                Task {
                    await SessionStore.shared.process(
                        .permissionSocketFailed(sessionId: sessionId, toolUseId: toolUseId)
                    )
                }
            }
        )
        Task { await SessionStore.shared.startZombieScan() }

        // Start TCP relay server for SSH connections
        startRelayTCPServer()
    }

    func startRelayTCPServer() {
        Task {
            let psk = await SSHHostRegistry.shared.getOrCreatePSK()
            HookSocketServer.shared.startTCPServer(
                port: 9871,
                psk: psk,
                onEvent: { event in
                    let start = Date()
                    Task {
                        await SessionStore.shared.process(.hookReceived(event))
                        let elapsed = Date().timeIntervalSince(start) * 1000
                        if elapsed > 50 {
                            Self.logger.warning("Event processing took \(elapsed, format: .fixed(precision: 1))ms: \(event.event, privacy: .public) sid=\(event.sessionId.prefix(8), privacy: .public)")
                        }
                    }

                    if event.sessionPhase == .processing {
                        Task { @MainActor in
                            InterruptWatcherManager.shared.startWatching(
                                sessionId: event.sessionId,
                                cwd: event.cwd
                            )
                        }
                    }

                    if event.status == "ended" {
                        Task { @MainActor in
                            InterruptWatcherManager.shared.stopWatching(sessionId: event.sessionId)
                        }
                    }

                    if event.event == "Stop" {
                        HookSocketServer.shared.cancelPendingPermissions(sessionId: event.sessionId)
                    }

                    if event.event == "PostToolUse", let toolUseId = event.toolUseId {
                        HookSocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
                    }
                },
                onCommand: { action, target, text in
                    Self.logger.debug("Relay command: \(action) target: \(target)")
                }
            )
            await MainActor.run {
                Self.logger.info("TCP relay server started on port 9871")
            }
        }
    }

    func stopMonitoring() {
        HookSocketServer.shared.stop()
        HookSocketServer.shared.stopTCPServer()
        Task { await SessionStore.shared.stopZombieScan() }
    }

    /// Remove all ended sessions from the store
    func clearEndedSessions() {
        Task { await SessionStore.shared.process(.clearEndedSessions) }
    }

    // MARK: - Permission Handling

    func approvePermission(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "allow"
            )

            await SessionStore.shared.process(
                .permissionApproved(sessionId: sessionId, toolUseId: permission.toolUseId)
            )
        }
    }

    func denyPermission(sessionId: String, reason: String?) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let permission = session.activePermission else {
                return
            }

            HookSocketServer.shared.respondToPermission(
                toolUseId: permission.toolUseId,
                decision: "deny",
                reason: reason
            )

            await SessionStore.shared.process(
                .permissionDenied(sessionId: sessionId, toolUseId: permission.toolUseId, reason: reason)
            )
        }
    }

    // MARK: - Question Handling

    func skipQuestion(sessionId: String) {
        Task {
            guard let session = await SessionStore.shared.session(for: sessionId),
                  let questionCtx = session.phase.questionContext else {
                return
            }

            await SessionStore.shared.process(
                .questionSkipped(sessionId: sessionId, toolUseId: questionCtx.toolUseId)
            )
        }
    }

    /// Archive (remove) a session from the instances list
    func archiveSession(sessionId: String) {
        Task {
            await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
        }
    }

    // MARK: - State Update

    private func updateFromSessions(_ sessions: [SessionState]) {
        instances = sessions
        pendingInstances = sessions.filter { $0.needsAttention }

        // Eagerly parse conversationInfo for sessions missing it
        for session in sessions where session.conversationInfo.firstUserMessage == nil {
            Task {
                let info = await ConversationParser.shared.parse(
                    sessionId: session.sessionId,
                    cwd: session.cwd
                )
                if info.firstUserMessage != nil {
                    await SessionStore.shared.updateConversationInfo(
                        sessionId: session.sessionId,
                        info: info
                    )
                }
            }
        }
    }

    // MARK: - History Loading (for UI)

    /// Request history load for a session
    func loadHistory(sessionId: String, cwd: String) {
        Task {
            await SessionStore.shared.process(.loadHistory(sessionId: sessionId, cwd: cwd))
        }
    }
}

// MARK: - Interrupt Watcher Delegate

extension ClaudeSessionMonitor: JSONLInterruptWatcherDelegate {
    nonisolated func didDetectInterrupt(sessionId: String) {
        Task {
            await SessionStore.shared.process(.interruptDetected(sessionId: sessionId))
        }

        Task { @MainActor in
            InterruptWatcherManager.shared.stopWatching(sessionId: sessionId)
        }
    }
}
