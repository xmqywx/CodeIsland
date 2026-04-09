//
//  PixelCharacterView.swift
//  ClaudeIsland
//
//  Pixel cat face animation engine.
//  Uses TimelineView(.animation) + Canvas for 60fps programmatic sprite rendering.
//  Cat design by user — 13x11 pixel grid.
//

import SwiftUI

// MARK: - Animation State

/// The 6 visual states the pixel character can display.
enum AnimationState: Sendable {
    case idle, working, needsYou, thinking, error, done
}

// MARK: - Pixel Character View

struct PixelCharacterView: View {
    let state: AnimationState

    /// Canvas size matches the 13x11 grid scaled by P.
    private static let gridW = 13
    private static let gridH = 11
    private static let P: CGFloat = 4
    static let canvasW: CGFloat = CGFloat(gridW) * P
    static let canvasH: CGFloat = CGFloat(gridH) * P

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let frame = Int(elapsed * 60)

                switch state {
                case .idle:
                    drawCatBase(context: &context)
                    drawIdleEyes(context: &context, frame: frame)
                case .working:
                    drawCatBase(context: &context)
                    drawWorkingEyes(context: &context, frame: frame)
                case .needsYou:
                    drawCatBase(context: &context)
                    drawNeedsYouEyes(context: &context)
                    drawEarTwitch(context: &context, frame: frame)
                case .thinking:
                    drawCatBase(context: &context)
                    drawThinkingEyes(context: &context)
                    drawBreathingNose(context: &context, frame: frame)
                case .error:
                    drawCatBase(context: &context)
                    drawErrorEyes(context: &context)
                case .done:
                    drawCatBase(context: &context)
                    drawDoneEyes(context: &context)
                }
            }
            .frame(width: Self.canvasW, height: Self.canvasH)
        }
    }

    // MARK: - Pixel Helper

    private func px(_ ctx: inout GraphicsContext, _ x: Int, _ y: Int, _ color: Color, _ alpha: Double = 1.0) {
        guard x >= 0 && x < Self.gridW && y >= 0 && y < Self.gridH else { return }
        let P = Self.P
        let rect = CGRect(x: CGFloat(x) * P, y: CGFloat(y) * P, width: P, height: P)
        ctx.fill(Path(rect), with: .color(color.opacity(alpha)))
    }

    // MARK: - Colors

    private static let W  = Color.white
    private static let G1 = Color(red: 0.576, green: 0.576, blue: 0.592)  // #939397
    private static let G3 = Color(red: 0.769, green: 0.769, blue: 0.780)  // #C4C4C7
    private static let G4 = Color(red: 0.898, green: 0.898, blue: 0.906)  // #E5E5E7
    private static let BK = Color(red: 0.067, green: 0.067, blue: 0.067)  // #111111
    private static let PK = Color(red: 0.957, green: 0.706, blue: 0.690)  // #F4B4B0
    private static let RD = Color(red: 0.937, green: 0.267, blue: 0.267)  // #EF4444
    private static let GN = Color(red: 0.290, green: 0.871, blue: 0.502)  // #4ADE80

    // MARK: - Cat Base (shared across all states)

    private func drawCatBase(context: inout GraphicsContext) {
        // Row 0: ear tips
        px(&context, 2, 0, Self.G4)
        px(&context, 10, 0, Self.G4)

        // Row 1: ears
        px(&context, 1, 1, Self.G4); px(&context, 2, 1, Self.W); px(&context, 3, 1, Self.G4)
        px(&context, 9, 1, Self.G4); px(&context, 10, 1, Self.W); px(&context, 11, 1, Self.G4)

        // Row 2: ears + stripe
        px(&context, 1, 2, Self.G4); px(&context, 2, 2, Self.W); px(&context, 3, 2, Self.W)
        px(&context, 4, 2, Self.G4); px(&context, 5, 2, Self.G1); px(&context, 6, 2, Self.G1); px(&context, 7, 2, Self.G1); px(&context, 8, 2, Self.G4)
        px(&context, 9, 2, Self.W); px(&context, 10, 2, Self.W); px(&context, 11, 2, Self.G4)

        // Row 3: head + stripe center
        px(&context, 1, 3, Self.G4); px(&context, 2, 3, Self.W); px(&context, 3, 3, Self.W); px(&context, 4, 3, Self.W); px(&context, 5, 3, Self.W)
        px(&context, 6, 3, Self.G3)
        px(&context, 7, 3, Self.W); px(&context, 8, 3, Self.W); px(&context, 9, 3, Self.W); px(&context, 10, 3, Self.W); px(&context, 11, 3, Self.G4)

        // Row 4: head
        px(&context, 1, 4, Self.G4); px(&context, 2, 4, Self.W); px(&context, 3, 4, Self.W); px(&context, 4, 4, Self.W); px(&context, 5, 4, Self.W)
        px(&context, 6, 4, Self.W)
        px(&context, 7, 4, Self.W); px(&context, 8, 4, Self.W); px(&context, 9, 4, Self.W); px(&context, 10, 4, Self.W); px(&context, 11, 4, Self.G4)

        // Row 5: eyes row — eyes drawn per-state, fill white here
        px(&context, 0, 5, Self.G4); px(&context, 1, 5, Self.W); px(&context, 2, 5, Self.W); px(&context, 3, 5, Self.W); px(&context, 4, 5, Self.W)
        px(&context, 5, 5, Self.W); px(&context, 6, 5, Self.W); px(&context, 7, 5, Self.W); px(&context, 8, 5, Self.W); px(&context, 9, 5, Self.W)
        px(&context, 10, 5, Self.W); px(&context, 11, 5, Self.W); px(&context, 12, 5, Self.G4)

        // Row 6: whiskers
        px(&context, 0, 6, Self.G1); px(&context, 1, 6, Self.G1)
        px(&context, 2, 6, Self.W); px(&context, 3, 6, Self.W); px(&context, 4, 6, Self.W); px(&context, 5, 6, Self.W)
        px(&context, 6, 6, Self.W); px(&context, 7, 6, Self.W); px(&context, 8, 6, Self.W); px(&context, 9, 6, Self.W); px(&context, 10, 6, Self.W)
        px(&context, 11, 6, Self.G1); px(&context, 12, 6, Self.G1)

        // Row 7: nose (default PK, overridden in thinking)
        px(&context, 0, 7, Self.G4); px(&context, 1, 7, Self.W); px(&context, 2, 7, Self.W); px(&context, 3, 7, Self.W); px(&context, 4, 7, Self.W)
        px(&context, 5, 7, Self.W); px(&context, 6, 7, Self.PK); px(&context, 7, 7, Self.W); px(&context, 8, 7, Self.W); px(&context, 9, 7, Self.W)
        px(&context, 10, 7, Self.W); px(&context, 11, 7, Self.W); px(&context, 12, 7, Self.G4)

        // Row 8: lower face
        px(&context, 1, 8, Self.G3); px(&context, 2, 8, Self.W); px(&context, 3, 8, Self.W); px(&context, 4, 8, Self.W); px(&context, 5, 8, Self.W)
        px(&context, 6, 8, Self.W); px(&context, 7, 8, Self.W); px(&context, 8, 8, Self.W); px(&context, 9, 8, Self.W); px(&context, 10, 8, Self.W); px(&context, 11, 8, Self.G3)

        // Row 9: chin
        px(&context, 2, 9, Self.G4); px(&context, 3, 9, Self.W); px(&context, 4, 9, Self.W); px(&context, 5, 9, Self.W)
        px(&context, 6, 9, Self.W); px(&context, 7, 9, Self.W); px(&context, 8, 9, Self.W); px(&context, 9, 9, Self.W); px(&context, 10, 9, Self.G4)

        // Row 10: bottom
        px(&context, 3, 10, Self.G4); px(&context, 4, 10, Self.G4); px(&context, 5, 10, Self.G4)
        px(&context, 6, 10, Self.G4); px(&context, 7, 10, Self.G4); px(&context, 8, 10, Self.G4); px(&context, 9, 10, Self.G4)
    }

    // MARK: - IDLE: normal eyes, blink

    private func drawIdleEyes(context: inout GraphicsContext, frame: Int) {
        if frame % 90 < 4 {
            px(&context, 3, 5, Self.G3)
            px(&context, 9, 5, Self.G3)
        } else {
            px(&context, 3, 5, Self.BK)
            px(&context, 9, 5, Self.BK)
        }
    }

    // MARK: - WORKING: eyes dart left-center-right

    private func drawWorkingEyes(context: inout GraphicsContext, frame: Int) {
        let dir = (frame / 15) % 3
        switch dir {
        case 0: // look left
            px(&context, 2, 5, Self.BK); px(&context, 8, 5, Self.BK)
        case 2: // look right
            px(&context, 4, 5, Self.BK); px(&context, 10, 5, Self.BK)
        default: // center
            px(&context, 3, 5, Self.BK); px(&context, 9, 5, Self.BK)
        }
    }

    // MARK: - NEEDS YOU: normal eyes + ear twitch

    private func drawNeedsYouEyes(context: inout GraphicsContext) {
        px(&context, 3, 5, Self.BK)
        px(&context, 9, 5, Self.BK)
    }

    private func drawEarTwitch(context: inout GraphicsContext, frame: Int) {
        let twitch = (frame / 14) % 2
        if twitch == 1 {
            // Right ear flicks — redraw ear tip shifted
            px(&context, 10, 0, Self.W) // clear original tip with white
            px(&context, 11, 0, Self.G4) // new tip position
        }
    }

    // MARK: - THINKING: eyes closed, breathing nose

    private func drawThinkingEyes(context: inout GraphicsContext) {
        px(&context, 3, 5, Self.G3)
        px(&context, 9, 5, Self.G3)
    }

    private func drawBreathingNose(context: inout GraphicsContext, frame: Int) {
        let breathe = 0.5 + sin(Double(frame) * 0.04) * 0.3
        px(&context, 6, 7, Self.PK, breathe)
    }

    // MARK: - ERROR: X eyes (red), static

    private func drawErrorEyes(context: inout GraphicsContext) {
        // Left X eye
        px(&context, 2, 4, Self.RD, 0.7); px(&context, 4, 4, Self.RD, 0.7)
        px(&context, 3, 5, Self.RD)
        px(&context, 2, 6, Self.RD, 0.7); px(&context, 4, 6, Self.RD, 0.7)

        // Right X eye
        px(&context, 8, 4, Self.RD, 0.7); px(&context, 10, 4, Self.RD, 0.7)
        px(&context, 9, 5, Self.RD)
        px(&context, 8, 6, Self.RD, 0.7); px(&context, 10, 6, Self.RD, 0.7)
    }

    // MARK: - DONE: heart eyes (green) + green tint on body

    private func drawDoneEyes(context: inout GraphicsContext) {
        // Green tint on the whole cat body (overlay)
        for y in 0..<Self.gridH {
            for x in 0..<Self.gridW {
                px(&context, x, y, Self.GN, 0.08)
            }
        }

        // Left heart eye ♥
        px(&context, 2, 5, Self.GN); px(&context, 4, 5, Self.GN)  // top bumps
        px(&context, 2, 4, Self.GN, 0.6); px(&context, 4, 4, Self.GN, 0.6)  // upper bumps
        px(&context, 3, 6, Self.GN)  // bottom point

        // Right heart eye ♥
        px(&context, 8, 5, Self.GN); px(&context, 10, 5, Self.GN)
        px(&context, 8, 4, Self.GN, 0.6); px(&context, 10, 4, Self.GN, 0.6)
        px(&context, 9, 6, Self.GN)
    }
}

// MARK: - SessionPhase → AnimationState Mapping

extension SessionPhase {
    var animationState: AnimationState {
        switch self {
        case .idle:
            return .idle
        case .processing:
            return .working
        case .waitingForApproval, .waitingForQuestion:
            return .needsYou
        case .waitingForInput:
            return .done
        case .compacting:
            return .thinking
        case .ended:
            return .idle
        }
    }
}
