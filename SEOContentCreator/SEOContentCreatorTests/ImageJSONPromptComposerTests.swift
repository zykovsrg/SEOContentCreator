import Testing
import Foundation
@testable import SEOContentCreator

struct ImageJSONPromptComposerTests {
    @Test func composeProducesValidJSONWithAllFields() throws {
        let fields = ImagePromptFields(
            style: "underground fashion photography",
            scene: "заброшенный склад",
            subject: "куртка из переработанных материалов",
            lightingType: "жёсткий",
            lightingSource: "прожектор сбоку",
            details: "текстура ткани видна крупным планом",
            camera: "широкоугольный объектив, низкий ракурс",
            mood: "дерзкий, индустриальный",
            aspectRatio: "3:2"
        )

        let json = ImageJSONPromptComposer.compose(fields)
        let data = try #require(json.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["style"] as? String == "underground fashion photography")
        #expect(object["scene"] as? String == "заброшенный склад")
        #expect(object["subject"] as? String == "куртка из переработанных материалов")
        #expect(object["details"] as? String == "текстура ткани видна крупным планом")
        #expect(object["camera"] as? String == "широкоугольный объектив, низкий ракурс")
        #expect(object["mood"] as? String == "дерзкий, индустриальный")
        #expect(object["aspect_ratio"] as? String == "3:2")
        let lighting = try #require(object["lighting"] as? [String: String])
        #expect(lighting["type"] == "жёсткий")
        #expect(lighting["source"] == "прожектор сбоку")
    }

    @Test func composeOmitsEmptyFields() throws {
        let fields = ImagePromptFields(subject: "только сюжет")
        let json = ImageJSONPromptComposer.compose(fields)
        let data = try #require(json.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object.count == 1)
        #expect(object["subject"] as? String == "только сюжет")
        #expect(object["lighting"] == nil)
    }

    @Test func composeOmitsLightingWhenBothSubfieldsEmpty() throws {
        let fields = ImagePromptFields(subject: "s", lightingType: "  ", lightingSource: "")
        let json = ImageJSONPromptComposer.compose(fields)
        let data = try #require(json.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["lighting"] == nil)
    }

    @Test func composeReturnsEmptyStringWhenAllFieldsEmpty() {
        #expect(ImageJSONPromptComposer.compose(ImagePromptFields()) == "")
    }

    @Test func aspectRatioMapsKnownSizes() {
        #expect(ImageJSONPromptComposer.aspectRatio(forSize: "1024x1024") == "1:1")
        #expect(ImageJSONPromptComposer.aspectRatio(forSize: "1024x1536") == "2:3")
        #expect(ImageJSONPromptComposer.aspectRatio(forSize: "1536x1024") == "3:2")
        #expect(ImageJSONPromptComposer.aspectRatio(forSize: "unknown") == "1:1")
    }
}
