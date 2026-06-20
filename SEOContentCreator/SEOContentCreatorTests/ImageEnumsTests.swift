import Testing
@testable import SEOContentCreator

struct ImageEnumsTests {
    @Test func imageRoleRoundTripsAndTitles() {
        for role in [ImageRole.cover, .illustration] {
            #expect(ImageRole(rawValue: role.rawValue) == role)
        }
        #expect(ImageRole.cover.title == "Обложка")
        #expect(ImageRole.illustration.title == "Иллюстрация")
    }

    @Test func imagePromptKindRoundTripsAndTitles() {
        #expect(ImagePromptKind.allCases.count == 2)
        for kind in ImagePromptKind.allCases {
            #expect(ImagePromptKind(rawValue: kind.rawValue) == kind)
        }
        #expect(ImagePromptKind.cover.title == "Обложка")
        #expect(ImagePromptKind.illustration.title == "Иллюстрация")
    }
}
