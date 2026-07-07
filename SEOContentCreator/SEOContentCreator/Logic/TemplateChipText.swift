// TemplateChipText.swift
import Foundation

/// Formats the compact "model · tokens · reasoning" chip shown on stage-prompt
/// rows in the Templates screen.
enum TemplateChipText {
    static func tokens(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        let k = Double(n) / 1000.0
        if k == k.rounded() { return "\(Int(k))k" }
        return String(format: "%.1fk", k)
    }

    static func chip(model: String, maxTokens: Int, reasoning: String?) -> String {
        var parts = [model, tokens(maxTokens)]
        if let reasoning, !reasoning.isEmpty { parts.append(reasoning) }
        return parts.joined(separator: " · ")
    }
}
