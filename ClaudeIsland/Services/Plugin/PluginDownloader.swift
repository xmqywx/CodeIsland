//
//  PluginDownloader.swift
//  ClaudeIsland
//
//  Fetches the plugin registry from GitHub and downloads
//  plugin packages for installation.
//

import Combine
import Foundation
import OSLog

@MainActor
final class PluginDownloader: ObservableObject {
    static let shared = PluginDownloader()
    private static let log = Logger(subsystem: "com.codeisland.app", category: "PluginDownloader")

    private let registryURL = URL(string: "https://raw.githubusercontent.com/IsleOS/codeisland-plugin-registry/main/registry.json")!

    @Published private(set) var availablePlugins: [RegistryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    struct RegistryEntry: Codable, Identifiable {
        let id: String
        let type: PluginType
        let name: String
        let version: String
        let author: String
        let price: Int
        let description: String?
        let tags: [String]?
        let downloadUrl: String
        let previewUrl: String?
    }

    struct RegistryResponse: Codable {
        let version: Int
        let updatedAt: String
        let plugins: [RegistryEntry]
    }

    // MARK: - Fetch

    func fetchRegistry() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: registryURL)
            let registry = try JSONDecoder().decode(RegistryResponse.self, from: data)
            availablePlugins = registry.plugins
            Self.log.info("Fetched \(registry.plugins.count) plugins from registry")
        } catch {
            lastError = error.localizedDescription
            Self.log.error("Failed to fetch registry: \(error)")
        }
    }

    /// Plugins from the registry that are not yet installed.
    var notInstalled: [RegistryEntry] {
        let installedIds = Set(PluginManager.shared.installedPlugins.map(\.id))
        return availablePlugins.filter { !installedIds.contains($0.id) }
    }

    /// Plugins that have a newer version available.
    var updatable: [RegistryEntry] {
        let installed = Dictionary(
            PluginManager.shared.installedPlugins.map { ($0.id, $0.version) },
            uniquingKeysWith: { first, _ in first }
        )
        return availablePlugins.filter { entry in
            guard let currentVersion = installed[entry.id] else { return false }
            return entry.version != currentVersion
        }
    }

    // MARK: - Download

    func download(_ entry: RegistryEntry) async throws {
        guard let baseURL = URL(string: entry.downloadUrl) else {
            throw URLError(.badURL)
        }
        let pluginJsonURL = baseURL.appendingPathComponent("plugin.json")

        // Download plugin.json
        let (jsonData, _) = try await URLSession.shared.data(from: pluginJsonURL)

        // Create temp dir
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-plugin-\(entry.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Save plugin.json
        try jsonData.write(to: tmpDir.appendingPathComponent("plugin.json"))

        // Download preview if exists
        if let previewUrlStr = entry.previewUrl, let previewUrl = URL(string: previewUrlStr) {
            if let (previewData, _) = try? await URLSession.shared.data(from: previewUrl) {
                let filename = previewUrl.lastPathComponent
                try? previewData.write(to: tmpDir.appendingPathComponent(filename))
            }
        }

        // Install to plugins dir
        let typeDir: String
        switch entry.type {
        case .theme: typeDir = "themes"
        case .buddy: typeDir = "buddies"
        case .sound: typeDir = "sounds"
        }
        try PluginManager.shared.install(pluginDir: tmpDir, type: typeDir, id: entry.id)

        // Cleanup
        try? FileManager.default.removeItem(at: tmpDir)

        Self.log.info("Downloaded and installed plugin \(entry.id)")
    }
}
