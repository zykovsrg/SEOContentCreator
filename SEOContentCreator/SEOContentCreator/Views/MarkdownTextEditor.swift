import SwiftUI
import AppKit

/// A plain-text NSTextView wrapper for editing Markdown, with Google-Docs-style
/// keyboard shortcuts that insert/toggle Markdown syntax around the selection
/// or current line. The stored text stays a plain Markdown string — there is
/// no rich-text/AttributedString conversion.
///
/// Shortcuts: Cmd+B bold (`**..**`), Cmd+I italic (`_.._`),
/// Cmd+Option+1/2/3 heading level 1/2/3 (`#`/`##`/`###` on the current line).
/// Cmd+1..3 are intentionally avoided — macOS reserves them for window tab
/// switching, which would swallow the key event before the text view sees it.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownEditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }
    }
}

/// Handles the Markdown keyboard shortcuts directly at the AppKit level, so
/// they work regardless of SwiftUI focus/selection-binding plumbing.
final class MarkdownEditorTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            if event.modifierFlags.contains(.option) {
                switch chars {
                case "1": setHeading(level: 1); return
                case "2": setHeading(level: 2); return
                case "3": setHeading(level: 3); return
                default: break
                }
            } else {
                switch chars {
                case "b": wrapSelection(prefix: "**", suffix: "**"); return
                case "i": wrapSelection(prefix: "_", suffix: "_"); return
                default: break
                }
            }
        }
        super.keyDown(with: event)
    }

    /// Wraps the current selection in `prefix`/`suffix`. With no selection,
    /// inserts an empty pair and places the cursor between them.
    private func wrapSelection(prefix: String, suffix: String) {
        let range = selectedRange()
        let ns = string as NSString
        let selected = ns.substring(with: range)
        let replacement = prefix + selected + suffix
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        let cursor = selected.isEmpty
            ? range.location + (prefix as NSString).length
            : range.location + (replacement as NSString).length
        setSelectedRange(NSRange(location: cursor, length: 0))
    }

    /// Replaces the leading `#`s (if any) on the current line with `level` of them.
    private func setHeading(level: Int) {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selectedRange())
        var line = ns.substring(with: lineRange)
        let hadTrailingNewline = line.hasSuffix("\n")
        if hadTrailingNewline { line.removeLast() }

        var body = Substring(line)
        while body.first == "#" { body = body.dropFirst() }
        if body.first == " " { body = body.dropFirst() }

        let newLine = String(repeating: "#", count: level) + " " + body + (hadTrailingNewline ? "\n" : "")
        guard shouldChangeText(in: lineRange, replacementString: newLine) else { return }
        replaceCharacters(in: lineRange, with: newLine)
        didChangeText()
        setSelectedRange(NSRange(location: lineRange.location + (newLine as NSString).length, length: 0))
    }
}
