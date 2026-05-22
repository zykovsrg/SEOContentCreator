import SwiftUI
import SwiftData

struct ProductBlocksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic
    var onGenerate: ([String]) -> Void

    // Starter set of product block names; refined in a later sub-project (Шаблоны).
    private let availableBlocks = ["CTA «Записаться»", "Почему мы", "Блок врача", "Преимущества клиники"]
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Выберите продуктовые блоки").font(.headline)
            List {
                ForEach(availableBlocks, id: \.self) { block in
                    Toggle(isOn: Binding(
                        get: { selected.contains(block) },
                        set: { if $0 { selected.insert(block) } else { selected.remove(block) } }
                    )) { Text(block) }
                }
            }
            HStack {
                Button("Отмена") { dismiss() }
                Spacer()
                Button("Сгенерировать") { onGenerate(Array(selected)); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding()
        .frame(width: 460, height: 360)
    }
}
