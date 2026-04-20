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
    private static let disabledOfficialsKey = "DisabledOfficialPlugins"

    @Published private(set) var loadedPlugins: [LoadedPlugin] = []
    @Published private(set) var disabledOfficialIds: Set<String> = []

    /// UI-facing list: loaded plugins + disabled officials shown as reinstall slots.
    struct PluginListItem: Identifiable {
        let id: String
        let name: String
        let icon: String
        let version: String
        let isOfficial: Bool
        let isInstalled: Bool
    }

    var pluginListItems: [PluginListItem] {
        var items: [PluginListItem] = loadedPlugins.map { plugin in
            PluginListItem(
                id: plugin.id,
                name: plugin.name,
                icon: plugin.icon,
                version: plugin.version,
                isOfficial: OfficialPlugins.ids.contains(plugin.id),
                isInstalled: true
            )
        }
        // Append disabled officials that aren't currently loaded
        for official in OfficialPlugins.all where disabledOfficialIds.contains(official.id) {
            if !items.contains(where: { $0.id == official.id }) {
                items.append(PluginListItem(
                    id: official.id,
                    name: official.name,
                    icon: official.icon,
                    version: official.version,
                    isOfficial: true,
                    isInstalled: false
                ))
            }
        }
        return items
    }

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

        /// Optional panel size hint. Two ways a plugin can provide one:
        ///   1. Runtime ObjC method `@objc func preferredPanelSize() -> NSValue`
        ///      (required for built-in Swift plugins, since they share
        ///       `Bundle.main` with the host and can't carry their own plist)
        ///   2. Info.plist keys `MioPluginPreferredWidth` / `MioPluginPreferredHeight`
        ///      (only consulted for external .bundle plugins — reading them
        ///       from `Bundle.main` would return the host's values)
        /// Returns nil when neither path yields a usable size, letting the
        /// host fall back to its default `(min(screenW*0.48, 620), min(screenH*0.78, 780))`.
        var preferredPanelSize: CGSize? {
            // Path 1: runtime selector
            let sel = NSSelectorFromString("preferredPanelSize")
            if instance.responds(to: sel),
               let raw = instance.perform(sel)?.takeUnretainedValue() as? NSValue {
                let size = raw.sizeValue
                if size.width >= 280, size.width <= 1200,
                   size.height >= 180, size.height <= 900 {
                    return CGSize(width: size.width, height: size.height)
                }
            }

            // Path 2: Info.plist — only valid for external bundles
            guard bundle !== Bundle.main,
                  let info = bundle.infoDictionary,
                  let rawW = (info["MioPluginPreferredWidth"] as? NSNumber)?.doubleValue,
                  let rawH = (info["MioPluginPreferredHeight"] as? NSNumber)?.doubleValue
            else {
                return nil
            }
            // Sanity clamp: reject absurdly small (< mini notch size) or
            // absurdly large (bigger than full-HD) hints.
            guard rawW >= 280, rawW <= 1200, rawH >= 180, rawH <= 900 else {
                return nil
            }
            return CGSize(width: rawW, height: rawH)
        }
    }

    /// Look up a loaded plugin by id. Used by NotchViewModel to ask for a
    /// panel size hint before allocating the expanded area.
    func plugin(id: String) -> LoadedPlugin? {
        loadedPlugins.first(where: { $0.id == id })
    }

    private var pluginsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codeisland/plugins")
    }

    // MARK: - Loading

    /// Register a built-in plugin (lives in the app, not a .bundle).
    func registerBuiltIn(_ plugin: MioPlugin) {
        let loaded = LoadedPlugin(
            id: plugin.id,
            name: plugin.name,
            icon: plugin.icon,
            version: plugin.version,
            instance: plugin as! NSObject,
            bundle: Bundle.main
        )
        loadedPlugins.append(loaded)
    }

    func loadAll() {
        // Load disabled-officials list from UserDefaults
        if let saved = UserDefaults.standard.array(forKey: Self.disabledOfficialsKey) as? [String] {
            disabledOfficialIds = Set(saved)
        }

        // Register Swift-built-in officials that aren't user-disabled.
        // Bundle-based officials (factory == nil) are loaded from disk in the scan below.
        for official in OfficialPlugins.all
        where !disabledOfficialIds.contains(official.id) && official.factory != nil {
            registerBuiltIn(official.factory!())
        }

        let fm = FileManager.default

        // Ensure the user plugins dir exists.
        if !fm.fileExists(atPath: pluginsDir.path) {
            try? fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        }

        // Scan two locations, in this order:
        //   1) user plugins dir  (~/.config/codeisland/plugins/)
        //   2) bundled plugins   (Code Island.app/Contents/Resources/Plugins/)
        //
        // User-installed plugins take precedence — duplicate IDs from the
        // bundled directory are skipped by loadPlugin(). This means users can
        // upgrade a built-in plugin via the marketplace without losing the
        // fallback when they delete the upgraded copy.
        var scanDirs: [URL] = [pluginsDir]
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Plugins"),
           fm.fileExists(atPath: bundled.path) {
            scanDirs.append(bundled)
        }

        for dir in scanDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in contents where url.pathExtension == "bundle" {
                loadPlugin(at: url)
            }
        }

        Self.log.info("Loaded \(self.loadedPlugins.count) native plugin(s)")
    }

    /// Tracks CFBundleIdentifier values whose code has already been loaded
    /// into this process. Loading the same Swift module twice from different
    /// paths triggers objc duplicate-class warnings ("_TtC... is implemented
    /// in both ...") and can cause spurious casting failures, so we dedupe
    /// *before* calling `loadAndReturnError()`.
    private var loadedBundleIdentifiers: Set<String> = []

    private func loadPlugin(at url: URL) {
        guard let bundle = Bundle(url: url) else {
            Self.log.warning("Failed to create bundle from \(url.lastPathComponent)")
            return
        }

        // Dedupe by CFBundleIdentifier before touching the dylib. This is
        // what keeps the built-in copy at /Applications/.../Resources/Plugins/
        // from clashing with a newer user-installed copy in ~/.config/.
        if let bundleId = bundle.bundleIdentifier {
            if loadedBundleIdentifiers.contains(bundleId) {
                Self.log.info("Skipping duplicate bundle \(url.lastPathComponent) — \(bundleId) already loaded")
                return
            }
            loadedBundleIdentifiers.insert(bundleId)
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

    /// Uninstall a plugin. For official plugins this marks them as disabled
    /// (so their slot stays visible and they can be re-enabled with one click).
    /// For third-party .bundle plugins this deletes the bundle from disk.
    func uninstall(id: String) {
        if OfficialPlugins.ids.contains(id) {
            disabledOfficialIds.insert(id)
            persistDisabledOfficials()
            unload(id: id)
            Self.log.info("Disabled official plugin: \(id)")
            return
        }
        guard let plugin = loadedPlugins.first(where: { $0.id == id }) else { return }
        // Only delete the file if it lives in our plugins dir, to avoid
        // nuking the app bundle itself if id collides.
        let bundlePath = plugin.bundle.bundleURL.path
        if bundlePath.hasPrefix(pluginsDir.path) {
            try? FileManager.default.removeItem(at: plugin.bundle.bundleURL)
        }
        unload(id: id)
        Self.log.info("Uninstalled plugin: \(id)")
    }

    /// Re-enable a previously-disabled official plugin.
    /// For Swift built-ins this re-registers the instance. For bundle-based
    /// officials (e.g. stats) this re-scans the plugins dir — the user needs
    /// to have installed the .bundle at least once, otherwise they should use
    /// the "Install from URL" flow.
    func reinstallOfficial(id: String) {
        guard let official = OfficialPlugins.info(id: id) else { return }
        disabledOfficialIds.remove(id)
        persistDisabledOfficials()
        if loadedPlugins.contains(where: { $0.id == id }) {
            return
        }
        if let factory = official.factory {
            registerBuiltIn(factory())
            Self.log.info("Re-enabled official plugin (built-in): \(id)")
            return
        }
        // Bundle-based: try to find an existing bundle on disk with matching id
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil
        ) {
            for url in contents where url.pathExtension == "bundle" {
                if let bundle = Bundle(url: url),
                   let info = bundle.infoDictionary?["MioPluginID"] as? String,
                   info == id {
                    loadPlugin(at: url)
                    Self.log.info("Re-enabled official plugin (bundle): \(id)")
                    return
                }
                // Fallback: match by lastPathComponent == "<id>.bundle"
                if url.lastPathComponent == "\(id).bundle" {
                    loadPlugin(at: url)
                    Self.log.info("Re-enabled official plugin (bundle by name): \(id)")
                    return
                }
            }
        }
        Self.log.warning("Official plugin \(id) has no bundle on disk — user must install from URL")
    }

    private func persistDisabledOfficials() {
        UserDefaults.standard.set(
            Array(disabledOfficialIds),
            forKey: Self.disabledOfficialsKey
        )
    }

    // MARK: - Install from URL

    enum InstallError: Error, LocalizedError {
        case invalidURL
        case downloadFailed(String)
        case extractionFailed(String)
        case bundleNotFound

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .downloadFailed(let msg): return "Download failed: \(msg)"
            case .extractionFailed(let msg): return "Extraction failed: \(msg)"
            case .bundleNotFound: return "No .bundle found in archive"
            }
        }
    }

    /// Download a .zip containing a .bundle plugin and install it.
    /// Used by the "Install from URL" flow in Settings.
    func installFromURL(_ urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw InstallError.invalidURL
        }

        // Download to a temp zip
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let zipURL = tmpDir.appendingPathComponent("plugin.zip")
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw InstallError.downloadFailed("HTTP \(http.statusCode)")
        }
        try FileManager.default.moveItem(at: downloadedURL, to: zipURL)

        // Extract using /usr/bin/ditto (handles macOS resource forks correctly)
        let extractDir = tmpDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw InstallError.extractionFailed(errStr)
        }

        // Find the .bundle directory inside the extracted tree
        guard let bundleURL = findBundle(in: extractDir) else {
            throw InstallError.bundleNotFound
        }

        // Copy into plugins dir (replace if exists)
        let fm = FileManager.default
        if !fm.fileExists(atPath: pluginsDir.path) {
            try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        }
        let dest = pluginsDir.appendingPathComponent(bundleURL.lastPathComponent)

        // If we're reinstalling an official plugin, unload the built-in first
        if let candidateBundle = Bundle(url: bundleURL),
           let candidateId = candidateBundle.infoDictionary?["MioPluginID"] as? String,
           OfficialPlugins.ids.contains(candidateId),
           !disabledOfficialIds.contains(candidateId) {
            unload(id: candidateId)
        }

        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: bundleURL, to: dest)
        loadPlugin(at: dest)
    }

    /// Recursively search for a .bundle directory.
    private func findBundle(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension == "bundle" {
                return url
            }
        }
        return nil
    }

    // MARK: - Query

    func plugin(for id: String) -> LoadedPlugin? {
        loadedPlugins.first(where: { $0.id == id })
    }
}
