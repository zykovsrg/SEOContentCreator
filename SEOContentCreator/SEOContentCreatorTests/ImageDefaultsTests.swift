import Testing
@testable import SEOContentCreator

struct ImageDefaultsTests {
    @Test func coverTemplateUsesThemeNotFragment() {
        let c = ImagePromptDefaults.content(for: .cover)
        #expect(c.contains("{{тема}}"))
        #expect(!c.contains("{{выделенный_фрагмент}}"))
    }

    @Test func illustrationTemplateUsesFragment() {
        let c = ImagePromptDefaults.content(for: .illustration)
        #expect(c.contains("{{тема}}"))
        #expect(c.contains("{{выделенный_фрагмент}}"))
    }

    @Test func templatesDoNotEmbedCompositionOrBackground() {
        for kind in ImagePromptKind.allCases {
            let c = ImagePromptDefaults.content(for: kind)
            #expect(!c.contains("Фон:"))
            #expect(!c.contains("Свет:"))
            #expect(!c.contains("16:9"))
            #expect(!c.contains("#"))
        }
    }

    @Test func defaultPresetsAreDistinctGlassStylesAtCoverSize() {
        let presets = ImageStylePresetDefaults.makeDefaults()
        #expect(presets.count == 2)
        #expect(Set(presets.map(\.name)).count == 2)
        for preset in presets {
            #expect(preset.styleText.contains("стекл"))
            #expect(preset.size == "1536x1024")
        }
    }

    @Test func resetDefaultMatchesByPresetName() {
        for def in ImageStylePresetDefaults.all {
            #expect(ImageStylePresetDefaults.matching(name: def.name)?.styleText == def.styleText)
        }
        #expect(ImageStylePresetDefaults.matching(name: "Не существующий пресет") == nil)
    }
}
