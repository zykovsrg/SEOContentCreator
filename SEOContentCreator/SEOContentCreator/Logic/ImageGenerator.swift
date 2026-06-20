import Foundation
import SwiftData

@MainActor
@Observable
final class ImageGenerator {
    typealias ImageProvider = (
        _ apiKey: String, _ prompt: String, _ model: String,
        _ size: String, _ quality: String, _ references: [Data]
    ) async throws -> Data
    typealias KeyProvider = () throws -> String

    var isRunning = false
    var lastErrorMessage: String?
    var previewData: Data?

    let model: String
    private let imageProvider: ImageProvider
    private let keyProvider: KeyProvider

    init(imageProvider: @escaping ImageProvider, keyProvider: @escaping KeyProvider, model: String) {
        self.imageProvider = imageProvider
        self.keyProvider = keyProvider
        self.model = model
    }

    static func live(model: String) -> ImageGenerator {
        ImageGenerator(
            imageProvider: { apiKey, prompt, model, size, quality, references in
                try await ImageClient().generate(
                    apiKey: apiKey, prompt: prompt, model: model,
                    size: size, quality: quality, references: references
                )
            },
            keyProvider: { try KeychainService.loadAPIKey() },
            model: model
        )
    }

    func render(
        topic: Topic, prompt: String, size: String, quality: String,
        references: [Data], in context: ModelContext
    ) async {
        isRunning = true
        lastErrorMessage = nil
        previewData = nil

        let job = GenerationJob(stageLabel: "image", agentName: "Генератор изображений", modelName: model)
        job.topic = topic
        context.insert(job)

        do {
            let key = try keyProvider()
            let data = try await imageProvider(key, prompt, model, size, quality, references)
            previewData = data
            job.status = .success
            job.finishedAt = .now
        } catch {
            job.status = .error
            job.finishedAt = .now
            let message: String
            if let keyError = error as? KeychainService.KeychainError, keyError == .notFound {
                message = "Укажите API-ключ в Настройках"
            } else {
                message = error.localizedDescription
            }
            job.errorMessage = message
            lastErrorMessage = message
        }

        isRunning = false
    }
}
