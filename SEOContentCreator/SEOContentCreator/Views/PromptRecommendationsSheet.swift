import SwiftUI

/// Read-only history of "Анализ и обучение" recommendations (FT-20260703-003).
/// Recommendations are never applied automatically — the user decides what to
/// change in the prompts under «Шаблоны» themselves.
struct PromptRecommendationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var topic: Topic

    private var sorted: [PromptRecommendation] {
        topic.promptRecommendations.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Рекомендации по промтам").font(.title2).bold()
                Spacer()
                Button("Закрыть") { dismiss() }
            }

            if sorted.isEmpty {
                ContentUnavailableView(
                    "Рекомендаций пока нет",
                    systemImage: "lightbulb",
                    description: Text("Запустите этап «Анализ и обучение», чтобы получить предложения по улучшению промтов.")
                )
            } else {
                List(sorted) { recommendation in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recommendation.problem).font(.headline)
                        Text(recommendation.location).font(.subheadline).foregroundStyle(.secondary)
                        Text(recommendation.suggestion).font(.body)
                        Text(recommendation.createdAt, style: .date)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding()
        .frame(width: 560, height: 520)
    }
}
