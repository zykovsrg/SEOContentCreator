// DesignSystem.swift
import SwiftUI
import AppKit

extension Color {
    /// Brand teal accent (the mockup's identity). Resolves per appearance so it
    /// stays legible in light and dark. Applied app-wide via `.tint`, so any
    /// control using `Color.accentColor` (selection, segmented, dots, buttons)
    /// follows it automatically.
    static let brandAccent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.176, green: 0.831, blue: 0.749, alpha: 1)  // #2DD4BF
            : NSColor(srgbRed: 0.051, green: 0.580, blue: 0.533, alpha: 1)  // #0D9488
    })

    /// Subtle panel fill for rails and inspector chrome.
    static let panelFill = Color(nsColor: .underPageBackgroundColor)

    /// Darker "page" behind the floating panels (mockup look).
    static let pageBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.075, green: 0.090, blue: 0.098, alpha: 1)   // #131717
            : NSColor(srgbRed: 0.914, green: 0.929, blue: 0.937, alpha: 1)   // #E9EDEF
    })

    /// The floating panel surface (slightly lighter than the page).
    static let panelSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.122, green: 0.149, blue: 0.157, alpha: 1)   // #1F2628
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    })

    static let controlSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.165, green: 0.192, blue: 0.200, alpha: 1)   // #2A3133
            : NSColor(srgbRed: 0.902, green: 0.925, blue: 0.929, alpha: 1)   // #E6ECEF
    })

    static let selectedControlSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.086, green: 0.105, blue: 0.110, alpha: 1)   // #161B1C
            : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    })

    static let rowHighlight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.059, green: 0.282, blue: 0.267, alpha: 1)   // #0F4844
            : NSColor(srgbRed: 0.886, green: 0.961, blue: 0.957, alpha: 1)   // #E2F5F4
    })

    static let hairline = Color(nsColor: .separatorColor)
}

extension View {
    /// Wraps content as a floating rounded panel on the page background,
    /// matching the mockup's inset-card layout.
    func panelCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension StatusTone {
    var color: Color {
        switch self {
        case .neutral:  return .secondary
        case .active:   return .orange
        case .positive: return .green
        }
    }
}

/// Colored status chip used in the content plan.
struct StatusPill: View {
    let label: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.color).frame(width: 6, height: 6)
            Text(label).font(.caption).fontWeight(.semibold)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(tone.color.opacity(0.14), in: Capsule())
        .foregroundStyle(tone.color)
    }
}

/// Compact 8-dot pipeline progress shown in the content-plan table.
struct StageProgressDots: View {
    /// One entry per `StagePipeline.workflow` stage, in order.
    let states: [StageState]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: state))
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func color(for state: StageState) -> Color {
        switch state {
        case .done:     return .green
        case .current:  return .accentColor
        case .upcoming: return Color.secondary.opacity(0.25)
        }
    }
}

/// Small monospaced metadata chip (e.g. "gpt-5.5 · 11k · high").
struct MetaChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.hairline.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(.secondary)
    }
}

struct EditorPanelTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.bold)
            .tracking(1.4)
            .foregroundStyle(.secondary)
    }
}
