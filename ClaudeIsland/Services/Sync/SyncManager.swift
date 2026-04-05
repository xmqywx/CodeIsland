//
//  SyncManager.swift
//  ClaudeIsland
//
//  Top-level coordinator for CodeLight Server sync.
//  Manages connection lifecycle, message relay, and RPC execution.
//

import Combine
import Foundation
import os.log

/// Coordinates all CodeLight Server sync functionality.
/// Initialize once at app startup, connects/disconnects based on configuration.
@MainActor
final class SyncManager: ObservableObject {

    static let shared = SyncManager()
    static let logger = Logger(subsystem: "com.codeisland", category: "SyncManager")

    @Published private(set) var isEnabled = false
    @Published private(set) var connectionState: ServerConnectionState = .disconnected

    private var connection: ServerConnection?
    private var relay: MessageRelay?
    private var rpcExecutor: RPCExecutor?

    /// The server URL to connect to. Stored in UserDefaults.
    var serverUrl: String? {
        get { UserDefaults.standard.string(forKey: "codelight-server-url") }
        set {
            UserDefaults.standard.set(newValue, forKey: "codelight-server-url")
            if let url = newValue, !url.isEmpty {
                Task { await connectToServer(url: url) }
            } else {
                disconnectFromServer()
            }
        }
    }

    private init() {
        // Default server URL if not configured
        if serverUrl == nil {
            UserDefaults.standard.set("https://island.wdao.chat", forKey: "codelight-server-url")
        }
        // Auto-connect on startup if configured
        if let url = serverUrl, !url.isEmpty {
            Task { await connectToServer(url: url) }
        }
    }

    // MARK: - Connection Lifecycle

    func connectToServer(url: String) async {
        disconnectFromServer()

        let conn = ServerConnection(serverUrl: url)
        self.connection = conn

        do {
            try await conn.authenticate()
            conn.connect()

            // Wait for socket to actually connect before starting relay
            let relay = MessageRelay(connection: conn)
            self.relay = relay
            let rpc = RPCExecutor()
            self.rpcExecutor = rpc

            // Delay relay start to give socket time to connect
            Task { @MainActor in
                // Wait up to 5 seconds for socket connection
                for _ in 0..<50 {
                    if conn.isConnected { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                if conn.isConnected {
                    relay.startRelaying()
                    Self.logger.info("Relay started after socket connected")
                } else {
                    Self.logger.warning("Socket did not connect in time, starting relay anyway")
                    relay.startRelaying()
                }
            }

            isEnabled = true
            connectionState = .connected
            Self.logger.info("Sync enabled with \(url)")
        } catch {
            connectionState = .error(error.localizedDescription)
            Self.logger.error("Sync connection failed: \(error)")
        }
    }

    func disconnectFromServer() {
        relay?.stopRelaying()
        connection?.disconnect()
        connection = nil
        relay = nil
        rpcExecutor = nil
        isEnabled = false
        connectionState = .disconnected
    }

    /// Called when a QR code is scanned with server details
    func handlePairingQR(serverUrl: String, tempPublicKey: String, deviceName: String) async {
        UserDefaults.standard.set(serverUrl, forKey: "codelight-server-url")
        await connectToServer(url: serverUrl)
        Self.logger.info("Paired with \(deviceName) via QR")
    }
}
