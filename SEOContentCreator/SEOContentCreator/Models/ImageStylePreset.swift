import Foundation
import SwiftData

@Model
final class ImageStylePreset {
    var uuid: UUID
    var name: String
    var styleText: String
    var referenceImageData: Data?
    var size: String
    var quality: String
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        styleText: String,
        referenceImageData: Data? = nil,
        size: String = "1024x1024",
        quality: String = "high"
    ) {
        self.uuid = UUID()
        self.name = name
        self.styleText = styleText
        self.referenceImageData = referenceImageData
        self.size = size
        self.quality = quality
        self.createdAt = .now
        self.updatedAt = .now
    }
}
