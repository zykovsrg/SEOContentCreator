// DesignSystem.swift
import SwiftUI

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
