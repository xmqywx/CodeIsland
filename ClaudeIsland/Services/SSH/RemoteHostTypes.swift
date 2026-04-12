//
//  RemoteHostTypes.swift
//  ClaudeIsland
//
//  Domain types for remote SSH host deployment.
//

import Foundation

// MARK: - Connection Mode

/// How the remote relay connects to Mac
enum ConnectionMode: String, Codable, Sendable, CaseIterable {
    /// Remote connects directly via TCP (same LAN or public IP)
    case direct
    /// Remote connects through SSH reverse tunnel (NAT scenario)
    case sshReverseTunnel

    var displayName: String {
        switch self {
        case .direct:
            return "Direct (LAN/PKI)"
        case .sshReverseTunnel:
            return "SSH Tunnel (NAT)"
        }
    }

    var description: String {
        switch self {
        case .direct:
            return "Remote connects directly to Mac. Use when on same network or with public IP."
        case .sshReverseTunnel:
            return "Remote connects via SSH tunnel. Use when Mac is behind NAT/firewall."
        }
    }
}

// MARK: - Daemon Status

/// Status of the relay daemon on remote machine
enum DaemonStatus: String, Codable, Sendable {
    case unknown
    case running
    case stopped
    case crashed

    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .running:
            return "Running"
        case .stopped:
            return "Stopped"
        case .crashed:
            return "Crashed"
        }
    }

    var icon: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .running:
            return "checkmark.circle.fill"
        case .stopped:
            return "stop.circle"
        case .crashed:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Deploy Status

/// Overall deployment status
enum DeployStatus: String, Codable, Sendable {
    case notDeployed
    case deploying
    case deployed
    case failed

    var displayName: String {
        switch self {
        case .notDeployed:
            return "Not Deployed"
        case .deploying:
            return "Deploying..."
        case .deployed:
            return "Deployed"
        case .failed:
            return "Failed"
        }
    }
}

// MARK: - Deploy Step

/// Individual step in the deployment process
enum DeployStep: String, Codable, Sendable {
    case precheck
    case connectSSH
    case prepareDirs
    case uploadFiles
    case writeConfig
    case startDaemon
    case verify

    var displayName: String {
        switch self {
        case .precheck:
            return "Checking prerequisites"
        case .connectSSH:
            return "Connecting via SSH"
        case .prepareDirs:
            return "Creating directories"
        case .uploadFiles:
            return "Uploading scripts"
        case .writeConfig:
            return "Writing configuration"
        case .startDaemon:
            return "Starting relay daemon"
        case .verify:
            return "Verifying connection"
        }
    }
}

// MARK: - Deploy Request

/// Request to deploy relay to a remote host
struct DeployRequest: Codable, Sendable {
    let hostId: UUID
    let relayHost: String
    let relayPort: Int
    let psk: String
    let enableVerification: Bool
}

// MARK: - Deploy Step Result

/// Result of a single deployment step
struct DeployStepResult: Codable, Sendable {
    let step: DeployStep
    let success: Bool
    let summary: String
    let rawLog: String?
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

// MARK: - Deploy Report

/// Complete report of a deployment operation
struct DeployReport: Codable, Sendable {
    let hostId: UUID
    let startedAt: Date
    var endedAt: Date
    var success: Bool
    var stepResults: [DeployStepResult]

    var totalDuration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var failedStep: DeployStepResult? {
        stepResults.first { !$0.success }
    }
}

// MARK: - Verify Result

/// Result of relay verification
struct VerifyResult: Codable, Sendable {
    let success: Bool
    let latencyMs: Double?
    let errorMessage: String?
}
