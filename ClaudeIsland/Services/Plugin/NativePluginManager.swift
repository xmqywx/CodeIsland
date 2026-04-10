//
//  NativePluginManager.swift
//  ClaudeIsland
//
//  Discovers, loads, and manages native .bundle plugins from
//  ~/.config/codeisland/plugins/
//

import AppKit
import Combine
import OSLog

@MainActor
final class NativePluginManager: ObservableObject {
    static let shared = NativePluginManager()
    private static let log = Logger(subsystem: "com.codeisland.app", category: "NativePluginManager")

    @Published private(set) var loadedPlugins: [LoadedPlugin] = []

    struct LoadedPlugin: Identifiable {
        let id: String
        let name: String
        let icon: String
        let version: String
        let instance: NSObject
        let bundle: Bundle

        func makeView() -> NSView? {
            instance.perform(Selector(("makeView")))?.takeUnretainedValue() as? NSView
        }

        /// Query a plugin for a UI slot view.
        /// Slots: "header", "footer", "overlay", "sessionItem"
        func viewForSlot(_ slot: String, context: [String: Any] = [:]) -> NSView? {
            let sel = NSSelectorFromString("viewForSlot:context:")
            guard instance.responds(to: sel) else { return nil }
            let result = instance.perform(sel, with: slot, with: context)
            return result?.takeUnretainedValue() as? NSView
        }
    }

    private var pluginsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codeisland/plugins")
    }

    // MARK: - Loading

    func loadAll() {
        let fm = FileManager.default
        let dir = pluginsDir

        // Create plugins dir if needed
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Scan for .bundle files
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            Self.log.info("No plugins directory or empty")
            return
        }

        for url in contents where url.pathExtension == "bundle" {
            loadPlugin(at: url)
        }

        Self.log.info("Loaded \(self.loadedPlugins.count) native plugin(s)")
    }

    private func loadPlugin(at url: URL) {
        guard let bundle = Bundle(url: url) else {
            Self.log.warning("Failed to create bundle from \(url.lastPathComponent)")
            return
        }

        do {
            try bundle.loadAndReturnError()
        } catch {
            NSLog("[NativePluginManager] Failed to load bundle %@: %@", url.lastPathComponent, error.localizedDescription)
            return
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            Self.log.warning("Bundle \(url.lastPathComponent) has no NSObject principal class")
            return
        }

        let instance = principalClass.init()

        // Use ObjC runtime to call MioPlugin methods — the protocol is defined
        // in both the app and the plugin, but they're different modules so we
        // can't cast directly. Instead we use responds(to:) + perform().
        guard instance.responds(to: Selector(("id"))),
              instance.responds(to: Selector(("name"))),
              instance.responds(to: Selector(("makeView"))) else {
            Self.log.warning("Principal class of \(url.lastPathComponent) missing MioPlugin methods")
            return
        }

        let pluginId = instance.value(forKey: "id") as? String ?? url.lastPathComponent
        let pluginName = instance.value(forKey: "name") as? String ?? pluginId
        let pluginIcon = instance.value(forKey: "icon") as? String ?? "puzzlepiece"
        let pluginVersion = instance.value(forKey: "version") as? String ?? "0.0.0"

        // Check for duplicate IDs
        if loadedPlugins.contains(where: { $0.id == pluginId }) {
            Self.log.warning("Duplicate plugin ID: \(pluginId), skipping")
            return
        }

        // Activate
        if instance.responds(to: Selector(("activate"))) {
            instance.perform(Selector(("activate")))
        }

        let loaded = LoadedPlugin(
            id: pluginId,
            name: pluginName,
            icon: pluginIcon,
            version: pluginVersion,
            instance: instance,
            bundle: bundle
        )
        loadedPlugins.append(loaded)
        Self.log.info("Loaded plugin: \(pluginName) v\(pluginVersion) (\(pluginId))")
    }

    // MARK: - Unloading

    func unloadAll() {
        for plugin in loadedPlugins {
            if plugin.instance.responds(to: Selector(("deactivate"))) {
                plugin.instance.perform(Selector(("deactivate")))
            }
        }
        loadedPlugins.removeAll()
    }

    func unload(id: String) {
        guard let index = loadedPlugins.firstIndex(where: { $0.id == id }) else { return }
        let plugin = loadedPlugins[index]
        if plugin.instance.responds(to: Selector(("deactivate"))) {
            plugin.instance.perform(Selector(("deactivate")))
        }
        loadedPlugins.remove(at: index)
        Self.log.info("Unloaded plugin: \(id)")
    }

    // MARK: - Install

    /// Install a .bundle file by copying it to the plugins directory.
    func install(bundleURL: URL) throws {
        let fm = FileManager.default
        let dest = pluginsDir.appendingPathComponent(bundleURL.lastPathComponent)

        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: bundleURL, to: dest)

        // Load the newly installed plugin
        loadPlugin(at: dest)
    }

    /// Uninstall a plugin by removing its .bundle from disk.
    func uninstall(id: String) {
        guard let plugin = loadedPlugins.first(where: { $0.id == id }) else { return }
        unload(id: id)
        try? FileManager.default.removeItem(at: plugin.bundle.bundleURL)
        Self.log.info("Uninstalled plugin: \(id)")
    }

    // MARK: - Query

    func plugin(for id: String) -> LoadedPlugin? {
        loadedPlugins.first(where: { $0.id == id })
    }
}
