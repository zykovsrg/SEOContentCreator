import Foundation
import SwiftData

enum ImageSaver {
    @discardableResult
    @MainActor
    static func saveGenerated(
        data: Data, role: ImageRole, prompt: String, fragment: String?,
        preset: ImageStylePreset?, model: String, topic: Topic, in context: ModelContext
    ) -> GeneratedImage {
        let image = GeneratedImage(
            role: role, data: data, promptUsed: prompt,
            presetID: preset?.uuid, presetNameSnapshot: preset?.name,
            anchorQuote: role == .illustration ? fragment : nil,
            sourceImageID: nil, modelName: model
        )
        image.topic = topic
        context.insert(image)
        if role == .cover && topic.coverImageID == nil {
            topic.coverImageID = image.uuid
        }
        topic.updatedAt = .now
        return image
    }

    @discardableResult
    @MainActor
    static func saveRefined(
        data: Data, source: GeneratedImage, prompt: String,
        preset: ImageStylePreset?, model: String, topic: Topic, in context: ModelContext
    ) -> GeneratedImage {
        let image = GeneratedImage(
            role: source.role, data: data, promptUsed: prompt,
            presetID: preset?.uuid, presetNameSnapshot: preset?.name,
            anchorQuote: source.anchorQuote,
            sourceImageID: source.uuid, modelName: model
        )
        image.topic = topic
        context.insert(image)
        topic.updatedAt = .now
        return image
    }
}
