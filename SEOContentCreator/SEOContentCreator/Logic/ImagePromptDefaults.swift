import Foundation

enum ImagePromptDefaults {
    static func content(for kind: ImagePromptKind) -> String {
        switch kind {
        case .cover:
            return """
            Сгенерируй обложку для медицинской статьи.
            Тема статьи: {{тема}}
            Обложка должна отражать тему и быть уместной для медицинского сайта клиники.
            """
        case .illustration:
            return """
            Сгенерируй иллюстрацию для статьи: {{тема}}
            Хочу проиллюстрировать эту часть текста:
            {{выделенный_фрагмент}}
            """
        }
    }
}
