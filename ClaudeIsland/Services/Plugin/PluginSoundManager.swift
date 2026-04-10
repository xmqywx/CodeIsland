//
//  PluginSoundManager.swift
//  ClaudeIsland
//
//  Plays plugin sound files (m4a/mp3) via AVAudioPlayer.
//  Coexists with the built-in SoundManager (synth engine).
//  Priority: if user has a plugin sound active, use it;
//  otherwise fall through to built-in synthesis.
//

import AVFAudio
import Combine
import Foundation
import OSLog

@MainActor
final class PluginSoundManager: ObservableObject {
    static let shared = PluginSoundManager()
    private static let log = Logger(subsystem: "com.codeisland.app", category: "PluginSoundManager")

    @Published var activeBGMPlugin: String? = nil
    private var bgmPlayer: AVAudioPlayer?

    private var pluginsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codeisland/plugins")
    }

    // MARK: - BGM

    func playBGM(pluginId: String) {
        stopBGM()
        let dir = pluginsDir.appendingPathComponent("sounds/\(pluginId)")
        guard let manifest = loadSoundManifest(from: dir),
              let bgmEntry = manifest.sounds["bgm"],
              let player = createPlayer(dir: dir, filename: bgmEntry.file) else {
            Self.log.warning("Failed to load BGM from plugin \(pluginId)")
            return
        }
        player.numberOfLoops = (bgmEntry.loop ?? true) ? -1 : 0
        player.volume = bgmEntry.volume ?? 0.3
        player.play()
        bgmPlayer = player
        activeBGMPlugin = pluginId
        Self.log.info("Playing BGM from plugin \(pluginId)")
    }

    func stopBGM() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        activeBGMPlugin = nil
    }

    // MARK: - Notification Sounds

    func playNotification(pluginId: String, event: SoundEvent) {
        let dir = pluginsDir.appendingPathComponent("sounds/\(pluginId)")
        guard let manifest = loadSoundManifest(from: dir),
              let entry = manifest.sounds[event.rawValue],
              let player = createPlayer(dir: dir, filename: entry.file) else {
            // No sound for this event in plugin — caller should fall back to synth
            return
        }
        player.volume = entry.volume ?? 0.7
        player.play()
    }

    /// Check if a plugin has a sound file for a given event.
    func hasSound(pluginId: String, event: SoundEvent) -> Bool {
        let dir = pluginsDir.appendingPathComponent("sounds/\(pluginId)")
        guard let manifest = loadSoundManifest(from: dir) else { return false }
        return manifest.sounds[event.rawValue] != nil
    }

    // MARK: - Helpers

    private func loadSoundManifest(from dir: URL) -> SoundManifest? {
        let url = dir.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SoundManifest.self, from: data)
    }

    private func createPlayer(dir: URL, filename: String) -> AVAudioPlayer? {
        let url = dir.appendingPathComponent("assets/\(filename)")
        return try? AVAudioPlayer(contentsOf: url)
    }
}
