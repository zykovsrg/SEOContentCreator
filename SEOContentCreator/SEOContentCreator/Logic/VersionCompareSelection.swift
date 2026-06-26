import Foundation

/// Toggles `tapped` in the compare selection, keeping at most two entries.
/// If already selected, it is removed. Otherwise appended; when this would
/// exceed two, the earliest selection is evicted (FIFO).
func compareSelectionToggle(current: [UUID], tapped: UUID) -> [UUID] {
    if let idx = current.firstIndex(of: tapped) {
        var next = current
        next.remove(at: idx)
        return next
    }
    var next = current + [tapped]
    if next.count > 2 { next.removeFirst() }
    return next
}
