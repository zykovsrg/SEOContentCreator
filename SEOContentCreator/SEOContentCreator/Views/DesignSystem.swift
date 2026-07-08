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
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.secondary)
    }
}
