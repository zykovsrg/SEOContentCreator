import Foundation

enum PreparationDestination: String, CaseIterable, Identifiable {
    case readerIntent
    case semantics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readerIntent: return "Задача читателя"
        case .semantics: return "Семантика"
        }
    }
}

struct PreparationPresentationState {
    var destination: PreparationDestination?

    mutating func open(_ destination: PreparationDestination) {
        self.destination = destination
    }
}
