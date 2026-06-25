import SwiftUI
import SwiftData

struct ProductBlocksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProductBlock.order) private var blocks: [ProductBlock]
    @Bindable var topic: Topic
    /// Передаёт промты выбранных блоков (а не имена).
    var onGenerate: ([String]) -> Void

    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Выберите продуктовые блоки").font(.headline)
            if blocks.isEmpty {
                ContentUnavailableView(
                    "Нет продуктовых блоков",
                    systemImage: "square.stack.3d.up",
                    description: Text("Добавьте блоки в разделе «Шаблоны».")
                )
            } else {
                List {
                    ForEach(blocks) { block in
                        Toggle(isOn: Binding(
                            get: { selected.contains(block.uuid) },
                            set: { if $0 { selected.insert(block.uuid) } else { selected.remove(block.uuid) } }
                        )) { Text(block.name) }
                    }
                }
            }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сгенерировать") {
                    let prompts = blocks
                        .filter { selected.contains($0.uuid) }
                        .map(\.prompt)
                    onGenerate(prompts)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 360)
    }
}
