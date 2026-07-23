import SwiftUI

struct SettingsView: View {
    @AppStorage("openAIModel") private var model = "gpt-4.1"
    @AppStorage("imageModel") private var imageModel = "gpt-image-1"
    @State private var apiKey = ""
    @State private var savedMessage: String?
    @State private var hasKey = KeychainService.hasAPIKey()
    @State private var googleClientID = ""
    @State private var googleClientSecret = ""
    @State private var hasGoogleClient = GoogleCredentialStore.hasClient
    @State private var isGoogleSignedIn = GoogleCredentialStore.isSignedIn
    @State private var googleMessage: String?
    @State private var auth = GoogleAuthService()

    @AppStorage("wordstatProviderKind") private var providerKindRaw = WordstatProviderKind.cloud.rawValue
    @State private var wordstatLegacyToken = ""
    @State private var wordstatLegacyMessage: String?
    @State private var hasWordstatLegacyToken = KeychainService.hasAPIKey(account: "wordstatLegacyToken")
    @State private var wordstatCloudAPIKey = ""
    @State private var wordstatCloudAPIKeyMessage: String?
    @State private var hasWordstatCloudAPIKey = KeychainService.hasAPIKey(account: "wordstatCloudAPIKey")
    @State private var wordstatCloudFolderID = ""
    @State private var wordstatCloudFolderIDMessage: String?
    @State private var hasWordstatCloudFolderID = KeychainService.hasAPIKey(account: "wordstatCloudFolderID")

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

            Section("Google Docs") {
                SecureField("Client ID", text: $googleClientID)
                SecureField("Client Secret", text: $googleClientSecret)
                HStack {
                    Button("Сохранить ключи") { saveGoogleClient() }
                        .disabled(googleClientID.isEmpty || googleClientSecret.isEmpty)
                    Spacer()
                    if hasGoogleClient {
                        Label("Ключи сохранены", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                HStack {
                    if isGoogleSignedIn {
                        Label("Подключено к Google", systemImage: "link").foregroundStyle(.green)
                        Button("Выйти", role: .destructive) { signOutGoogle() }
                    } else {
                        Button("Войти в Google") { Task { await signInGoogle() } }
                            .disabled(!hasGoogleClient)
                    }
                }
                if let googleMessage {
                    Text(googleMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Wordstat") {
                Picker("Провайдер Wordstat", selection: $providerKindRaw) {
                    ForEach(WordstatProviderKind.allCases, id: \.rawValue) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }

                SecureField("Токен Wordstat (старый API)", text: $wordstatLegacyToken)
                Text("Для api.wordstat.yandex.net. По данным на 2026-07-22 этот API отвечает ошибкой TLS-сертификата — сохраните токен на случай, если Яндекс это исправит.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Сохранить токен") { saveWordstatLegacyToken() }
                        .disabled(wordstatLegacyToken.isEmpty)
                    Spacer()
                    if hasWordstatLegacyToken {
                        Label("Токен сохранён", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                if let wordstatLegacyMessage {
                    Text(wordstatLegacyMessage).font(.caption).foregroundStyle(.secondary)
                }

                SecureField("Ключ Yandex Cloud", text: $wordstatCloudAPIKey)
                Text("Тот же ключ, что используется для YandexGPT в AI Studio.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Сохранить ключ") { saveWordstatCloudAPIKey() }
                        .disabled(wordstatCloudAPIKey.isEmpty)
                    Spacer()
                    if hasWordstatCloudAPIKey {
                        Label("Ключ сохранён", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                if let wordstatCloudAPIKeyMessage {
                    Text(wordstatCloudAPIKeyMessage).font(.caption).foregroundStyle(.secondary)
                }

                TextField("Yandex Cloud folderId", text: $wordstatCloudFolderID)
                Text("Идентификатор каталога в Yandex Cloud — не секрет, но обязателен для каждого запроса.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Сохранить folderId") { saveWordstatCloudFolderID() }
                        .disabled(wordstatCloudFolderID.isEmpty)
                    Spacer()
                    if hasWordstatCloudFolderID {
                        Label("folderId сохранён", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                if let wordstatCloudFolderIDMessage {
                    Text(wordstatCloudFolderIDMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 480)
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

    private func saveGoogleClient() {
        do {
            try GoogleCredentialStore.saveClient(id: googleClientID, secret: googleClientSecret)
            googleClientID = ""; googleClientSecret = ""
            hasGoogleClient = true
            googleMessage = "Ключи Google сохранены в Keychain."
        } catch {
            googleMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func signInGoogle() async {
        do {
            try await auth.signIn()
            isGoogleSignedIn = true
            googleMessage = "Вход выполнен."
        } catch {
            googleMessage = (error as? LocalizedError)?.errorDescription ?? "Вход не удался."
        }
    }

    private func signOutGoogle() {
        auth.signOut()
        isGoogleSignedIn = false
        googleMessage = "Выход выполнен."
    }

    private func saveWordstatLegacyToken() {
        do {
            try WordstatCredentialStore.saveLegacyToken(wordstatLegacyToken)
            wordstatLegacyToken = ""
            hasWordstatLegacyToken = true
            wordstatLegacyMessage = "Токен сохранён в Keychain."
        } catch {
            wordstatLegacyMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func saveWordstatCloudAPIKey() {
        do {
            try WordstatCredentialStore.saveCloudAPIKey(wordstatCloudAPIKey)
            wordstatCloudAPIKey = ""
            hasWordstatCloudAPIKey = true
            wordstatCloudAPIKeyMessage = "Ключ сохранён в Keychain."
        } catch {
            wordstatCloudAPIKeyMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func saveWordstatCloudFolderID() {
        do {
            try WordstatCredentialStore.saveCloudFolderID(wordstatCloudFolderID)
            wordstatCloudFolderID = ""
            hasWordstatCloudFolderID = true
            wordstatCloudFolderIDMessage = "folderId сохранён в Keychain."
        } catch {
            wordstatCloudFolderIDMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }
}
