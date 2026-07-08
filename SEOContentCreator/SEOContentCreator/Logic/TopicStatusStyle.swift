// TopicStatusStyle.swift
import Foundation

/// Semantic severity for status chips. The view layer maps each tone to a
/// concrete color; keeping the mapping here makes it unit-testable.
enum StatusTone: Equatable {
    case neutral   // idea / not started
    case active    // in progress, ready to work
    case positive  // done / published
}

extension TopicStatus {
    var tone: StatusTone {
        switch self {
        case .brief:      return .neutral
        case .inProgress: return .active
        case .done, .published: return .positive
        }
    }
}
