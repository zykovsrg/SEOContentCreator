import Foundation

enum ImageStylePresetDefaults {
    static let name = "Фирменный стиль клиники"
    static let styleText = """
    Палитра (используй эти цвета): #F4F9FF, #E8F1FF, #D9E8FD, #007AC0.
    На изображении не должно быть текста.
    Иллюстрация для пациента: объясняет медицинскую информацию людям без специальных знаний в медицине.
    Чистый, аккуратный, дружелюбный медицинский стиль.
    """

    static func makeDefault() -> ImageStylePreset {
        ImageStylePreset(name: name, styleText: styleText)
    }
}
