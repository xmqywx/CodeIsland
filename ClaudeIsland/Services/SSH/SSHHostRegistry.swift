//
//  SSHHostRegistry.swift
//  ClaudeIsland
//
//  Manages SSH host configurations and per-host connection state.
//

import Combine
import Foundation
import os.log

/// Manages registered SSH hosts and their connection states
actor SSHHostRegistry {
    static let shared = SSHHostRegistry()

    nonisolated static let logger = Logger(subsystem: "com.codeisland", category: "SSH")

    // MARK: - State

    private var hosts: [UUID: SSHHost] = [:]

    // MARK: - Published State

    private nonisolated(unsafe) let hostsSubject = CurrentValueSubject<[SSHHost], Never>([])

    nonisolated var hostsPublisher: AnyPublisher<[SSHHost], Never> {
        hostsSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - CRUD

    func addHost(host: String, user: String, port: Int = 22, sshKeyPath: String? = nil, connectionMode: ConnectionMode = .sshReverseTunnel) -> SSHHost {
        // All hosts share the same local relay port (9871) since Mac runs one TCP server
        let localPort = 9871

        let entry = SSHHost(
            id: UUID(),
            host: host,
            user: user,
            port: port,
            localPort: localPort,
            sshKeyPath: sshKeyPath,
            connectionMode: connectionMode,
            connectionState: .disconnected
        )

        hosts[entry.id] = entry
        saveToUserDefaults()
        publish()

        Self.logger.info("Added SSH host \(entry.host) on local port \(entry.localPort)")
        print("[SSHHostRegistry] addHost: \(user)@\(host): port=\(port), total hosts=\(hosts.count)")
        return entry
    }

    func removeHost(id: UUID) {
        hosts.removeValue(forKey: id)
        saveToUserDefaults()
        publish()
    }

    func updateHost(_ host: SSHHost) {
        hosts[host.id] = host
        saveToUserDefaults()
        publish()
    }

    func updateConnectionState(hostId: UUID, state: SSHConnectionState) {
        if var host = hosts[hostId] {
            host.connectionState = state
            hosts[hostId] = host
            publish()
        }
    }

    func getHost(id: UUID) -> SSHHost? {
        return hosts[id]
    }

    func getHostByAddress(host: String, user: String) -> SSHHost? {
        return hosts.values.first { $0.host == host && $0.user == user }
    }

    func currentHosts() -> [SSHHost] {
        return Array(hosts.values)
    }

    // MARK: - PSK Management

    private var psk: String?

    func getOrCreatePSK() -> String {
        if let existing = psk {
            return existing
        }
        // Load from Keychain or generate new
        if let stored = loadPSKFromKeychain() {
            psk = stored
            return stored
        }
        let newPSK = generateRandomPSK()
        savePSKToKeychain(newPSK)
        psk = newPSK
        return newPSK
    }

    // MARK: - Persistence

    private let userDefaultsKey = "SSHHostRegistry.hosts"

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([UUID: SSHHost].self, from: data) else {
            Self.logger.info("loadFromUserDefaults: no data found, hosts=\(self.hosts.count)")
            return
        }
        hosts = decoded
        Self.logger.info("loadFromUserDefaults: loaded \(self.hosts.count) hosts")
        publish()
    }

    private func saveToUserDefaults() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
        Self.logger.info("saveToUserDefaults: saved \(self.hosts.count) hosts")
    }

    // MARK: - Keychain

    private let keychainPSKKey = "com.codeisland.ssh-relay.psk"

    private func generateRandomPSK() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func savePSKToKeychain(_ psk: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainPSKKey,
            kSecValueData as String: psk.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadPSKFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainPSKKey,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let psk = String(data: data, encoding: .utf8) else {
            return nil
        }
        return psk
    }

    // MARK: - Publish

    private func publish() {
        let list = Array(hosts.values)
        Task { @MainActor in
            self.hostsSubject.send(list)
        }
    }
}

// MARK: - SSHHost

struct SSHHost: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var host: String
    var user: String
    var port: Int
    var localPort: Int
    var sshKeyPath: String?
    var connectionMode: ConnectionMode
    var connectionState: SSHConnectionState
}
