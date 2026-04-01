//
//  SoundManager.swift
//  ClaudeIsland
//
//  8-bit chiptune sound system for session state transitions.
//  Fires sounds on SessionPhase changes, not continuously.
//

import AppKit
import Combine
import Foundation

// MARK: - Sound Events

/// All distinct sound events in the app, each mappable to an 8-bit .wav file.
enum SoundEvent: String, CaseIterable {
    case sessionStart = "session_start"
    case processingBegins = "processing_begins"
    case needsApproval = "needs_approval"
    case approvalGranted = "approval_granted"
    case approvalDenied = "approval_denied"
    case sessionComplete = "session_complete"
    case error = "error"
    case compacting = "compacting"

    /// Human-readable label for display in settings UI
    var displayName: String {
        L10n.soundEventName(self.rawValue)
    }

    /// Default enabled state for each event
    var defaultEnabled: Bool {
        switch self {
        case .sessionStart: return true
        case .processingBegins: return false
        case .needsApproval: return true
        case .approvalGranted: return true
        case .approvalDenied: return true
        case .sessionComplete: return true
        case .error: return true
        case .compacting: return false
        }
    }
}

// MARK: - Sound Manager

/// Singleton manager for 8-bit chiptune sound playback.
/// Sounds fire on session state transitions only, triggered by `SessionPhase` changes.
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private let defaults = UserDefaults.standard

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let globalMute = "soundManager.globalMute"
        static let volume = "soundManager.volume"

        static func eventEnabled(_ event: SoundEvent) -> String {
            "soundManager.event.\(event.rawValue).enabled"
        }
    }

    // MARK: - Published Properties

    /// Master mute toggle. When true, no sounds play.
    @Published var globalMute: Bool {
        didSet { defaults.set(globalMute, forKey: Keys.globalMute) }
    }

    /// Master volume (0.0 ... 1.0).
    @Published var volume: Float {
        didSet { defaults.set(volume, forKey: Keys.volume) }
    }

    // MARK: - Init

    private init() {
        // Load globalMute (defaults to false if not set)
        self.globalMute = defaults.bool(forKey: Keys.globalMute)

        // Load volume (defaults to 0.7 if not previously saved)
        if defaults.object(forKey: Keys.volume) != nil {
            self.volume = defaults.float(forKey: Keys.volume)
        } else {
            self.volume = 0.7
        }
    }

    // MARK: - Per-Event Enabled

    /// Returns whether a given sound event is enabled.
    func isEnabled(_ event: SoundEvent) -> Bool {
        let key = Keys.eventEnabled(event)
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return event.defaultEnabled
    }

    /// Sets the enabled state for a given sound event.
    func setEnabled(_ enabled: Bool, for event: SoundEvent) {
        defaults.set(enabled, forKey: Keys.eventEnabled(event))
        objectWillChange.send()
    }

    // MARK: - Playback

    /// Play the sound associated with an event, respecting mute and per-event settings.
    func play(_ event: SoundEvent) {
        guard !globalMute else { return }
        guard isEnabled(event) else { return }

        // TODO: Replace with bundled 8-bit .wav from Resources/Sounds/
        // Future implementation:
        //   if let sound = NSSound(named: event.rawValue) {
        //       sound.volume = volume
        //       sound.play()
        //   }
        NSSound.beep()
    }

    // MARK: - Phase Transition Handling

    /// Maps `SessionPhase` transitions to sound events and plays the appropriate sound.
    /// Call this whenever a session's phase changes.
    func handlePhaseTransition(from oldPhase: SessionPhase, to newPhase: SessionPhase) {
        // Determine which sound event (if any) corresponds to this transition
        let event: SoundEvent? = {
            switch newPhase {
            case .processing:
                // If coming from idle, this is a new session starting
                if case .idle = oldPhase {
                    return .sessionStart
                }
                // If coming from waitingForApproval, approval was granted
                if case .waitingForApproval = oldPhase {
                    return .approvalGranted
                }
                // Otherwise, processing is beginning (e.g. from waitingForInput)
                return .processingBegins

            case .waitingForApproval:
                return .needsApproval

            case .waitingForInput:
                // If coming from waitingForApproval, approval was denied and Claude stopped
                if case .waitingForApproval = oldPhase {
                    return .approvalDenied
                }
                // Processing finished normally
                return .sessionComplete

            case .idle:
                // If coming from waitingForApproval, approval was denied
                if case .waitingForApproval = oldPhase {
                    return .approvalDenied
                }
                return nil

            case .compacting:
                return .compacting

            case .ended:
                return .sessionComplete
            }
        }()

        if let event {
            play(event)
        }
    }
}
