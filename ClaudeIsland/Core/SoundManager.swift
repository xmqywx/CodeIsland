//
//  SoundManager.swift
//  ClaudeIsland
//
//  8-bit chiptune sound system for session state transitions.
//  Uses AVAudioEngine + AVAudioSourceNode for programmatic synthesis.
//  Each event has a unique frequency pattern — no external files needed.
//

import AVFAudio
import Combine
import Foundation

// MARK: - Sound Events

/// All distinct sound events in the app, each mappable to a synthesized tone.
enum SoundEvent: String, CaseIterable {
    case sessionStart = "session_start"
    case processingBegins = "processing_begins"
    case needsApproval = "needs_approval"
    case approvalGranted = "approval_granted"
    case approvalDenied = "approval_denied"
    case sessionComplete = "session_complete"
    case error = "error"
    case compacting = "compacting"
    case rateLimitWarning = "rate_limit_warning"

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
        case .rateLimitWarning: return true
        }
    }
}

// MARK: - Tone Descriptor

/// Describes a single tone segment for synthesis.
private struct ToneSegment {
    let frequency: Float       // Hz (0 = silence)
    let duration: Float        // seconds
    let waveform: Waveform
    let endFrequency: Float?   // non-nil for frequency sweeps

    enum Waveform {
        case sine
        case square
    }

    init(frequency: Float, duration: Float, waveform: Waveform = .sine, endFrequency: Float? = nil) {
        self.frequency = frequency
        self.duration = duration
        self.waveform = waveform
        self.endFrequency = endFrequency
    }
}

// MARK: - Sound Manager

/// Singleton manager for 8-bit chiptune sound playback.
/// Sounds fire on session state transitions only, triggered by `SessionPhase` changes.
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private let defaults = UserDefaults.standard
    private let audioEngine = AVAudioEngine()
    private var isEngineRunning = false
    private let synthesisQueue = DispatchQueue(label: "com.codeisland.sound-synthesis", qos: .userInteractive)

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

    // MARK: - Note Frequencies (Hz)

    private enum Note {
        static let A3: Float = 220.00
        static let C4: Float = 261.63
        static let E4: Float = 329.63
        static let G4: Float = 392.00
        static let A5: Float = 880.00   // actually A5
        static let C5: Float = 523.25
        static let E5: Float = 659.25
        static let F5: Float = 698.46
        static let G5: Float = 783.99
        static let C6: Float = 1046.50
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

    // MARK: - Tone Patterns

    /// Returns the sequence of tone segments for a given sound event.
    private func tonePattern(for event: SoundEvent) -> [ToneSegment] {
        switch event {
        case .sessionStart:
            // Ascending two-tone: C5 -> E5
            return [
                ToneSegment(frequency: Note.C5, duration: 0.100),
                ToneSegment(frequency: Note.E5, duration: 0.100),
            ]

        case .processingBegins:
            // Single short blip: G4
            return [
                ToneSegment(frequency: Note.G4, duration: 0.050),
            ]

        case .needsApproval:
            // Urgent two-tone alert: A5 -> F5 -> A5
            return [
                ToneSegment(frequency: Note.A5, duration: 0.080),
                ToneSegment(frequency: Note.F5, duration: 0.080),
                ToneSegment(frequency: Note.A5, duration: 0.080),
            ]

        case .approvalGranted:
            // Happy chord: C5+E5+G5 played together
            // We simulate by playing all three as a combined waveform
            return [
                ToneSegment(frequency: Note.C5, duration: 0.150),  // chord marker
            ]

        case .approvalDenied:
            // Low descending: E4 -> C4
            return [
                ToneSegment(frequency: Note.E4, duration: 0.100),
                ToneSegment(frequency: Note.C4, duration: 0.100),
            ]

        case .sessionComplete:
            // Victory fanfare: C5 -> E5 -> G5 -> C6
            return [
                ToneSegment(frequency: Note.C5, duration: 0.080),
                ToneSegment(frequency: Note.E5, duration: 0.080),
                ToneSegment(frequency: Note.G5, duration: 0.080),
                ToneSegment(frequency: Note.C6, duration: 0.080),
            ]

        case .error:
            // Buzzer: A3 square wave
            return [
                ToneSegment(frequency: Note.A3, duration: 0.200, waveform: .square),
            ]

        case .compacting:
            // Whoosh: frequency sweep 800 -> 200 Hz
            return [
                ToneSegment(frequency: 800, duration: 0.150, waveform: .sine, endFrequency: 200),
            ]

        case .rateLimitWarning:
            // Urgent warning: descending alarm tone A5 -> E4 -> A5 -> E4
            return [
                ToneSegment(frequency: Note.A5, duration: 0.120, waveform: .square),
                ToneSegment(frequency: Note.E4, duration: 0.120, waveform: .square),
                ToneSegment(frequency: Note.A5, duration: 0.120, waveform: .square),
                ToneSegment(frequency: Note.E4, duration: 0.180, waveform: .square),
            ]
        }
    }

    // MARK: - Audio Buffer Generation

    /// Generate a PCM buffer for a sequence of tone segments.
    private func generateBuffer(segments: [ToneSegment], sampleRate: Double, volume: Float, isChord: Bool = false) -> AVAudioPCMBuffer? {
        let totalDuration = segments.reduce(Float(0)) { $0 + $1.duration }
        let frameCount = AVAudioFrameCount(Double(totalDuration) * sampleRate)
        guard frameCount > 0 else { return nil }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        if isChord {
            // Chord mode: mix C5+E5+G5 simultaneously
            let chordFreqs: [Float] = [Note.C5, Note.E5, Note.G5]
            let chordDuration = segments[0].duration
            let chordFrames = Int(Double(chordDuration) * sampleRate)
            let amplitude = volume * 0.25  // Lower per-voice to avoid clipping

            for frame in 0..<min(chordFrames, Int(frameCount)) {
                var sample: Float = 0
                for freq in chordFreqs {
                    let phase = 2.0 * Float.pi * freq * Float(frame) / Float(sampleRate)
                    sample += sin(phase) * amplitude
                }
                // Apply envelope (fade in/out to avoid clicks)
                let fadeFrames = min(Int(0.005 * sampleRate), chordFrames / 4)
                let envelope: Float
                if frame < fadeFrames {
                    envelope = Float(frame) / Float(fadeFrames)
                } else if frame > chordFrames - fadeFrames {
                    envelope = Float(chordFrames - frame) / Float(fadeFrames)
                } else {
                    envelope = 1.0
                }
                channelData[frame] = sample * envelope
            }
        } else {
            // Sequential segments
            var frameOffset = 0
            for segment in segments {
                let segmentFrames = Int(Double(segment.duration) * sampleRate)
                let amplitude = volume * 0.35
                let fadeFrames = min(Int(0.003 * sampleRate), segmentFrames / 4)

                for frame in 0..<segmentFrames {
                    guard frameOffset + frame < Int(frameCount) else { break }

                    // Calculate frequency (possibly sweeping)
                    let freq: Float
                    if let endFreq = segment.endFrequency {
                        let progress = Float(frame) / Float(segmentFrames)
                        freq = segment.frequency + (endFreq - segment.frequency) * progress
                    } else {
                        freq = segment.frequency
                    }

                    let phase = 2.0 * Float.pi * freq * Float(frame) / Float(sampleRate)
                    let rawSample: Float
                    switch segment.waveform {
                    case .sine:
                        rawSample = sin(phase)
                    case .square:
                        rawSample = sin(phase) >= 0 ? 1.0 : -1.0
                    }

                    // Envelope to avoid clicks
                    let envelope: Float
                    if frame < fadeFrames {
                        envelope = Float(frame) / Float(fadeFrames)
                    } else if frame > segmentFrames - fadeFrames {
                        envelope = Float(segmentFrames - frame) / Float(fadeFrames)
                    } else {
                        envelope = 1.0
                    }

                    channelData[frameOffset + frame] = rawSample * amplitude * envelope
                }
                frameOffset += segmentFrames
            }
        }

        return buffer
    }

    // MARK: - Playback

    /// Play the sound associated with an event, respecting mute and per-event settings.
    func play(_ event: SoundEvent) {
        guard !globalMute else { return }
        guard isEnabled(event) else { return }

        // If user has a plugin notification sound pack active, use that instead
        if let pluginId = NotchCustomizationStore.shared.customization.notificationSoundPlugin,
           PluginSoundManager.shared.hasSound(pluginId: pluginId, event: event) {
            PluginSoundManager.shared.playNotification(pluginId: pluginId, event: event)
            return
        }

        let currentVolume = volume
        let segments = tonePattern(for: event)
        let isChord = (event == .approvalGranted)

        synthesisQueue.async { [weak self] in
            guard let self = self else { return }
            self.playSynthesized(segments: segments, volume: currentVolume, isChord: isChord)
        }
    }

    /// Generate and play a synthesized tone on the audio engine.
    private func playSynthesized(segments: [ToneSegment], volume: Float, isChord: Bool) {
        let sampleRate: Double = 44100

        guard let buffer = generateBuffer(segments: segments, sampleRate: sampleRate, volume: volume, isChord: isChord) else {
            return
        }

        // Create a fresh player node for each sound
        let playerNode = AVAudioPlayerNode()

        // All engine mutations must be serialized
        let mainFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))

        if !isEngineRunning {
            do {
                try audioEngine.start()
                isEngineRunning = true
            } catch {
                // If engine fails to start, detach and bail
                audioEngine.detach(playerNode)
                return
            }
        }

        // Schedule buffer and auto-detach when done
        playerNode.scheduleBuffer(buffer) { [weak self] in
            // Clean up after playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                playerNode.stop()
                self?.audioEngine.detach(playerNode)
            }
        }
        playerNode.play()
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

            case .waitingForQuestion:
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
