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
        case .idea:      return .neutral
        case .ready:     return .active
        case .published: return .positive
        }
    }
}
