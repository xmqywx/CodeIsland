//
//  BuddyReader.swift
//  CodeIsland
//
//  Reads Claude Code buddy (companion) data from ~/.claude.json
//

import Combine
import Foundation

struct BuddyInfo: Sendable {
    let name: String
    let personality: String
    let species: BuddySpecies
    let hatchedAt: Date?
}

enum BuddySpecies: String, CaseIterable, Sendable {
    case duck, goose, cat, rabbit, owl, penguin, turtle, snail
    case dragon, octopus, axolotl, ghost, robot, blob, cactus, mushroom, chonk, capybara
    case unknown

    /// Detect species from personality text
    static func detect(from personality: String) -> BuddySpecies {
        let lower = personality.lowercased()
        for species in BuddySpecies.allCases where species != .unknown {
            if lower.contains(species.rawValue) {
                return species
            }
        }
        return .unknown
    }

    /// Emoji for display
    var emoji: String {
        switch self {
        case .duck: return "🦆"
        case .goose: return "🪿"
        case .cat: return "🐱"
        case .rabbit: return "🐰"
        case .owl: return "🦉"
        case .penguin: return "🐧"
        case .turtle: return "🐢"
        case .snail: return "🐌"
        case .dragon: return "🐉"
        case .octopus: return "🐙"
        case .axolotl: return "🦎"
        case .ghost: return "👻"
        case .robot: return "🤖"
        case .blob: return "🫧"
        case .cactus: return "🌵"
        case .mushroom: return "🍄"
        case .chonk: return "🐈"
        case .capybara: return "🦫"
        case .unknown: return "🐾"
        }
    }
}

class BuddyReader: ObservableObject {
    static let shared = BuddyReader()

    @Published var buddy: BuddyInfo?

    private let claudeJsonPath: URL

    private init() {
        claudeJsonPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: claudeJsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let companion = json["companion"] as? [String: Any],
              let name = companion["name"] as? String,
              let personality = companion["personality"] as? String else {
            buddy = nil
            return
        }

        let hatchedAt: Date?
        if let ts = companion["hatchedAt"] as? Double {
            hatchedAt = Date(timeIntervalSince1970: ts / 1000.0)
        } else {
            hatchedAt = nil
        }

        let species = BuddySpecies.detect(from: personality)

        buddy = BuddyInfo(
            name: name,
            personality: personality,
            species: species,
            hatchedAt: hatchedAt
        )
    }
}
