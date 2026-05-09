//
//  Redemption.swift
//  ClaudeIsland
//
//  Mac-side redemption record + typed errors mirroring the server
//  contract for `POST /v1/pairing/redeem-code`. The Mac is the trial
//  redemption point now (Apple Guideline 3.1.1 forced the input off
//  iOS) — the iPhone inherits paid status via DeviceLink at pair time
//  and via the `subscription-updated` socket event when already paired.
//
//  The Mac itself doesn't gate any features on subscription state today.
//  This file exists purely so the Pair Phone panel can show "已激活 X
//  天试用 · 到期 YYYY-MM-DD" persistently after a successful redeem.
//

import Foundation

/// One successful redemption snapshot. Persisted to UserDefaults under
/// `MioIsland.lastRedemption` so the banner survives app relaunches.
struct RedemptionRecord: Codable, Equatable {
    let code: String
    let durationDays: Int
    let redeemedAt: Date
    let expiresAt: Date

    /// Banner-relevant: only display while still in the trial window.
    /// After expiry the banner hides; the user can redeem a fresh code.
    var isActive: Bool { expiresAt > Date() }

    /// "5月8日" / "May 8, 2026" — short, locale-aware. Reserved for the
    /// detail row; the headline banner uses `daysLeft` for parity
    /// with the iPhone's "(剩余 N 天)" label.
    var formattedExpiry: String {
        let f = DateFormatter()
        f.locale = L10n.isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f.string(from: expiresAt)
    }

    /// Whole days until expiry, rounded *up*. Field name aligned with
    /// iPhone + server (`daysLeft` everywhere) so all three platforms
    /// say the same thing. Picked ceil() to match consumer-app
    /// conventions: 18 hours left → "剩余 1 天", not "剩余 0 天".
    /// Past-expiry returns 0 — caller hides the banner via `isActive`.
    var daysLeft: Int {
        let secs = expiresAt.timeIntervalSince(Date())
        guard secs > 0 else { return 0 }
        return max(1, Int(ceil(secs / 86400)))
    }
}

/// Server-contract-aligned error keys. The Mac switches on the `error`
/// string from the response body, NOT HTTP status — server may collapse
/// 4xx into a single 400 while keeping the body shape stable. Keep this
/// enum's raw values in sync with server team's `error` field values.
enum RedeemError: Error, Equatable {
    case unauthorized
    case notAMac
    case invalidCode
    case codeExhausted
    case codeExpired
    case codeRevoked
    case alreadyRedeemed
    case rateLimited
    case serverError
    case network
    case malformedResponse

    /// Build from the server's machine-readable `error` field. Unknown
    /// values fall back to .serverError so we still surface *some*
    /// message instead of silently swallowing a new error class.
    init(serverErrorKey raw: String) {
        switch raw {
        case "unauthorized":     self = .unauthorized
        case "not_a_mac":        self = .notAMac
        case "invalid_code":     self = .invalidCode
        case "code_exhausted":   self = .codeExhausted
        case "code_expired":     self = .codeExpired
        case "code_revoked":     self = .codeRevoked
        case "already_redeemed": self = .alreadyRedeemed
        case "rate_limited":     self = .rateLimited
        case "server_error":     self = .serverError
        default:                 self = .serverError
        }
    }

    /// Human-readable message rendered under the input. All strings live
    /// in L10n so the en/zh swap is automatic with the system setting.
    var displayMessage: String {
        switch self {
        case .unauthorized:      return L10n.redeemErrorUnauthorized
        case .notAMac:           return L10n.redeemErrorNotAMac
        case .invalidCode:       return L10n.redeemErrorInvalidCode
        case .codeExhausted:     return L10n.redeemErrorCodeExhausted
        case .codeExpired:       return L10n.redeemErrorCodeExpired
        case .codeRevoked:       return L10n.redeemErrorCodeRevoked
        case .alreadyRedeemed:   return L10n.redeemErrorAlreadyRedeemed
        case .rateLimited:       return L10n.redeemErrorRateLimited
        case .serverError:       return L10n.redeemErrorServerError
        case .network:           return L10n.redeemErrorNetwork
        case .malformedResponse: return L10n.redeemErrorServerError
        }
    }
}
