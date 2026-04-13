//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let anthropicProxyURL = "anthropicProxyURL"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Anthropic API Proxy
    //
    // URLSession.shared on macOS GUI apps only honors System Preferences →
    // Network → Proxies, not shell env vars. Users in network-restricted
    // regions typically run a local HTTP/SOCKS proxy (Clash / V2Ray) on
    // something like 127.0.0.1:7890 and expect the app to use it. We store
    // a user-supplied proxy URL here and apply it ONLY to Anthropic API
    // calls (RateLimitMonitor). Requests to our own sync server stay direct.

    /// User-configured proxy URL for Anthropic API requests, e.g. "http://127.0.0.1:7890".
    /// Empty string / nil means no proxy (direct connection).
    static var anthropicProxyURL: String {
        get { defaults.string(forKey: Keys.anthropicProxyURL) ?? "" }
        set { defaults.set(newValue, forKey: Keys.anthropicProxyURL) }
    }

    /// Build a URLSession for Anthropic API requests, applying the user's
    /// proxy URL if configured. Callers should reuse the returned session
    /// per-request; it's cheap to construct but not worth caching because
    /// users can change the proxy setting at runtime.
    static func makeAnthropicSession() -> URLSession {
        let config = URLSessionConfiguration.default
        let raw = anthropicProxyURL.trimmingCharacters(in: .whitespaces)
        if !raw.isEmpty,
           let parsed = parseProxy(raw) {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: 1,
                kCFNetworkProxiesHTTPProxy: parsed.host,
                kCFNetworkProxiesHTTPPort: parsed.port,
                kCFNetworkProxiesHTTPSEnable: 1,
                "HTTPSProxy": parsed.host,
                "HTTPSPort": parsed.port,
            ]
        }
        return URLSession(configuration: config)
    }

    /// Accepts "http://host:port", "https://host:port", or bare "host:port".
    private static func parseProxy(_ raw: String) -> (host: String, port: Int)? {
        var s = raw
        if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
        }
        // Strip any trailing path.
        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let port = Int(parts[1]), !parts[0].isEmpty else {
            return nil
        }
        return (parts[0], port)
    }

    /// Apply the user's `anthropicProxyURL` preference to CodeIsland's own
    /// process environment via POSIX `setenv`. Called once at startup from
    /// `AppDelegate.init()` and again whenever the preference changes.
    ///
    /// Why process env and not just `URLSession.connectionProxyDictionary`?
    /// Because many plugins (Stats' Editor's Note, future shell-outs) spawn
    /// the `claude` CLI — or other CLIs — via `Foundation.Process`, whose
    /// network stack is independent of Swift `URLSession`. Subprocesses
    /// inherit their parent's environment, so setting HTTPS_PROXY / HTTP_PROXY
    /// / ALL_PROXY on CodeIsland's own process means every subprocess
    /// automatically picks it up — no per-plugin opt-in, no global
    /// `launchctl setenv` pollution affecting other GUI apps.
    ///
    /// This is the architectural answer to "why does proxy coverage keep
    /// being a whack-a-mole" — instead of wiring every new network
    /// consumer individually, we set it once on the process and inherit.
    ///
    /// Idempotent: non-empty value → `setenv`. Empty value is a **no-op** —
    /// we do NOT `unsetenv`, because the process may have inherited proxy
    /// env vars from `launchctl setenv` (set by the user outside CodeIsland)
    /// and clearing them would silently break users who depend on that
    /// global fallback. The trade-off: if the user **had** a proxy set here
    /// and then clears the field, subprocesses spawned in this session
    /// still see the previously-set value until the app is restarted. The
    /// rate-limit bar (`URLSession`-based) picks up the change immediately
    /// because it re-reads the setting per request.
    ///
    /// Safe to call on every `UserDefaults.didChangeNotification`.
    static func applyProxyToProcessEnvironment() {
        let raw = anthropicProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let keys = ["HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY",
                    "https_proxy", "http_proxy", "all_proxy"]
        for k in keys { setenv(k, raw, 1) }
    }
}
