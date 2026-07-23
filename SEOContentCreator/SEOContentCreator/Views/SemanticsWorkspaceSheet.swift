import SwiftUI

struct SemanticsWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    var body: some View {
        VStack(spacing: 0) {
            if topic.readerIntent == nil {
                Label(
                    "Задача читателя не заполнена. Семантику можно собрать, "
                    + "но оценка интересов и практической цели аудитории будет менее точной.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                Divider()
            }

            SemanticsEditorSheet(topic: topic)

            Divider()
            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 920, height: 720)
    }
}
