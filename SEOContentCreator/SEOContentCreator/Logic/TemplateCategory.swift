// TemplateCategory.swift
import Foundation

/// Top-level categories for the Templates screen.
enum TemplateCategory: String, CaseIterable, Identifiable {
    case stages         // Этапы (prompt + role + context blocks merged per stage)
    case images         // Изображения (промты + пресеты)
    case skills         // Скиллы
    case forbidden      // Фразы (запрещённые формулировки + словарь правок)
    case semantics      // Семантика (минус-слова + вопросительные маски)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stages:    return "Этапы"
        case .images:    return "Изображения"
        case .skills:    return "Скиллы"
        case .forbidden: return "Фразы"
        case .semantics: return "Семантика"
        }
    }
}
