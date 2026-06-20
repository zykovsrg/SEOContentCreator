import Foundation
import SwiftData

enum PublishMode: String, Codable, Equatable {
    case newDocument
    case overwrite
}

@Model
final class ExternalDocument {
    var uuid: UUID
    var docID: String
    var docURL: String
    var modeRaw: String
    var publishedAt: Date

    @Relationship var topic: Topic?

    init(docID: String, docURL: String, mode: PublishMode, publishedAt: Date = .now) {
        self.uuid = UUID()
        self.docID = docID
        self.docURL = docURL
        self.modeRaw = mode.rawValue
        self.publishedAt = publishedAt
    }

    var mode: PublishMode {
        get { PublishMode(rawValue: modeRaw) ?? .newDocument }
        set { modeRaw = newValue.rawValue }
    }
}
