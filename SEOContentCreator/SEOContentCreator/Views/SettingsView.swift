import SwiftUI

struct SettingsView: View {
    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @AppStorage("imageModel") private var imageModel = "gpt-image-1"
    @State private var apiKey = ""
    @State private var savedMessage: String?
    @State private var hasKey = KeychainService.hasAPIKey()

    private let models = [
        "gpt-5.5-pro", "gpt-5.5",
        "gpt-5.4-pro", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano",
        "gpt-5.3-chat-latest",
        "gpt-4.1", "gpt-4o", "gpt-4o-mini"
    ]

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API-ключ", text: $apiKey)
                Picker("Модель", selection: $model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("Сохранить ключ") { saveKey() }
                        .disabled(apiKey.isEmpty)
                    if hasKey {
                        Button("Удалить ключ", role: .destructive) { deleteKey() }
                    }
                    Spacer()
                    if hasKey {
                        Label("Ключ сохранён", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                if let savedMessage {
                    Text(savedMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Изображения") {
                TextField("Модель изображений", text: $imageModel)
                Text("Например: gpt-image-1 или gpt-image-2. Используется тот же API-ключ OpenAI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 320)
        .navigationTitle("Настройки")
    }

    private func saveKey() {
        do {
            try KeychainService.save(apiKey: apiKey)
            apiKey = ""
            hasKey = true
            savedMessage = "Ключ сохранён в Keychain."
        } catch {
            savedMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func deleteKey() {
        try? KeychainService.deleteAPIKey()
        hasKey = false
        savedMessage = "Ключ удалён."
    }
}
