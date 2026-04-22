//
//  PixelCardBackground.swift
//  ClaudeIsland
//
//  Reusable dot-grid "pixel card" background inspired by
//  reactbits.dev/components/pixel-card. A regular grid of tiny dots,
//  most dark, a few accent-colored. On hover, dots within a radius
//  around the mouse brighten and a slow wave pulses across the grid.
//
//  Usage:
//      .background(PixelCardBackground(cornerRadius: 14))
//

import SwiftUI

struct PixelCardBackground: View {
    var cornerRadius: CGFloat = 14
    var gridSpacing: CGFloat = 5
    var dotSize: CGFloat = 1.4
    var baseColor: Color = Color(red: 0.06, green: 0.07, blue: 0.10)
    var accentColors: [Color] = [
        Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255),   // lime
        Color(red: 0x7A/255, green: 0xE6/255, blue: 0xFF/255),   // cyan
        Color(red: 0xB4/255, green: 0xA0/255, blue: 0xFF/255)    // purple
    ]
    /// Radius around cursor where dots brighten (points).
    var spotlightRadius: CGFloat = 90

    @State private var mouseLocation: CGPoint? = nil
    @State private var isHovering: Bool = false
    @State private var hoverIntensity: Double = 0
    @State private var pulsePhase: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Solid base underlay — Canvas draws dots on top
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                baseColor,
                                baseColor.opacity(0.92)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                // Animated dot grid
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    Canvas { context, size in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        // Slow breathing phase so even without hover, the grid has life
                        let breathe = (sin(now * 0.7) * 0.5 + 0.5)
                        let cols = Int(size.width / gridSpacing)
                        let rows = Int(size.height / gridSpacing)

                        // Stable pseudo-random seed per (col,row) — drives accent picks + alpha variance
                        for r in 0..<rows {
                            for c in 0..<cols {
                                let x = CGFloat(c) * gridSpacing + gridSpacing / 2
                                let y = CGFloat(r) * gridSpacing + gridSpacing / 2

                                let seed = abs((c &* 73) ^ (r &* 151)) % 100

                                // Base brightness — most dots are subtle, a few are brighter
                                var alpha = 0.07 + (Double(seed) / 100.0) * 0.10

                                // Ambient wave — a diagonal ripple pulses slowly
                                let wavePhase = (Double(c + r) * 0.22) + now * 1.1
                                let wave = (sin(wavePhase) * 0.5 + 0.5) * 0.15
                                alpha += wave * (0.4 + breathe * 0.6)

                                // Mouse spotlight — dots within `spotlightRadius` glow
                                if let mouse = mouseLocation {
                                    let dx = x - mouse.x
                                    let dy = y - mouse.y
                                    let dist = sqrt(dx * dx + dy * dy)
                                    if dist < spotlightRadius {
                                        let t = 1 - (dist / spotlightRadius)
                                        // Smoothstep-ish falloff
                                        let falloff = t * t * (3 - 2 * t)
                                        alpha += Double(falloff) * 0.85 * hoverIntensity
                                    }
                                }

                                // Clamp
                                alpha = min(alpha, 1.0)

                                // Accent color for ~8% of dots, weighted by seed
                                let isAccent = seed > 91
                                let color: Color
                                if isAccent {
                                    let i = seed % accentColors.count
                                    color = accentColors[i]
                                } else {
                                    color = .white
                                }

                                let rect = CGRect(
                                    x: x - dotSize / 2,
                                    y: y - dotSize / 2,
                                    width: dotSize,
                                    height: dotSize
                                )
                                context.fill(
                                    Path(ellipseIn: rect),
                                    with: .color(color.opacity(alpha))
                                )
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                // Gradient border
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: isHovering
                                ? [
                                    Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255).opacity(0.35),
                                    Color(red: 0x7A/255, green: 0xE6/255, blue: 0xFF/255).opacity(0.18),
                                    Color.white.opacity(0.08)
                                  ]
                                : [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.04)
                                  ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovering ? 0.9 : 0.6
                    )
            }
            // Track mouse continuously while it's over the card
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    mouseLocation = location
                    if !isHovering {
                        withAnimation(.easeOut(duration: 0.25)) {
                            isHovering = true
                            hoverIntensity = 1.0
                        }
                    }
                case .ended:
                    mouseLocation = nil
                    withAnimation(.easeOut(duration: 0.4)) {
                        isHovering = false
                        hoverIntensity = 0
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: mouseLocation)
        }
    }
}
