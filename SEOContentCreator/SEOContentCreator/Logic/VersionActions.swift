import Foundation

enum VersionActions {
    /// Build a hybrid text: take paragraph i from `new` if i is accepted, else from `old`.
    /// Paragraphs are aligned by index; if `new` has more paragraphs, extra accepted ones are appended.
    static func assembleHybrid(old: String, new: String, acceptedNewIndices: Set<Int>) -> String {
        let oldParas = ParagraphDiff.paragraphs(old)
        let newParas = ParagraphDiff.paragraphs(new)
        let count = max(oldParas.count, newParas.count)
        var result: [String] = []
        for i in 0..<count {
            if acceptedNewIndices.contains(i), i < newParas.count {
                result.append(newParas[i])
            } else if i < oldParas.count {
                result.append(oldParas[i])
            }
        }
        return result.joined(separator: "\n\n")
    }
}
