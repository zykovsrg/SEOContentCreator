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

    @Test func templatesDoNotEmbedStyle() {
        for kind in ImagePromptKind.allCases {
            let c = ImagePromptDefaults.content(for: kind)
            #expect(!c.contains("#F4F9FF"))
        }
    }

    @Test func defaultPresetCarriesBrandPalette() {
        let preset = ImageStylePresetDefaults.makeDefault()
        #expect(preset.styleText.contains("#F4F9FF"))
        #expect(preset.styleText.contains("#007AC0"))
        #expect(!preset.name.isEmpty)
    }
}
