// TemplateCategory.swift
import Foundation

/// Top-level categories for the Templates screen, replacing the single long
/// list of 8 sections with a category selector.
enum TemplateCategory: String, CaseIterable, Identifiable {
    case stagePrompts   // Промты этапов
    case roles          // ИИ-роли
    case editorial      // Редполитика и источники
    case images         // Изображения (промты + пресеты)
    case skills         // Скиллы
    case forbidden      // Запрещённые формулировки

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stagePrompts: return "Промты этапов"
        case .roles:        return "Роли"
        case .editorial:    return "Редполитика"
        case .images:       return "Изображения"
        case .skills:       return "Скиллы"
        case .forbidden:    return "Фразы"
        }
    }
}
