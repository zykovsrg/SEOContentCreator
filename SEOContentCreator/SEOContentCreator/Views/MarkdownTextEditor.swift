import SwiftUI
import AppKit

/// A plain-text NSTextView wrapper for editing Markdown, with Google-Docs-style
/// keyboard shortcuts that insert/toggle Markdown syntax around the selection
/// or current line. The stored text stays a plain Markdown string — there is
/// no rich-text/AttributedString conversion. Background highlighting (see
/// `highlightRange`) uses `NSLayoutManager` temporary attributes, which are
/// display-only and never touch the stored string.
///
/// Shortcuts: Cmd+B bold (`**..**`), Cmd+I italic (`_.._`),
/// Cmd+Option+1/2/3 heading level 1/2/3 (`#`/`##`/`###` on the current line),
/// Cmd+Shift+K wraps the selection in `[[БЛОК]]`/`[[/БЛОК]]` markers (see
/// `CommercialBlockSplitter`). Cmd+1..3 are intentionally avoided — macOS
/// reserves them for window tab switching, which would swallow the key event
/// before the text view sees it.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)
    /// Set to `false` to make the editor temporarily read-only, e.g. while a
    /// fragment regeneration is in flight or awaiting accept/reject.
    var isEditable: Bool = true
    /// Called whenever the text view's selection changes. `range.length == 0`
    /// means an empty (caret-only) selection; `rect` is the selection's
    /// bounding box in the enclosing `NSScrollView`'s coordinate space (nil
    /// when the selection is empty), for positioning a SwiftUI overlay button.
    var onSelectionChange: (NSRange, CGRect?) -> Void = { _, _ in }
    /// When non-nil, this range gets a temporary highlighted background — used
    /// to mark a freshly regenerated fragment awaiting accept/reject.
    var highlightRange: NSRange?
    /// Bump this (e.g. `+= 1`) to programmatically wrap the current selection
    /// in `[[БЛОК]]`/`[[/БЛОК]]` markers from SwiftUI, without going through
    /// the Cmd+Shift+K keyboard shortcut — e.g. a toolbar button in
    /// `EditorSheet`. Any change in value triggers the wrap exactly once.
    var commercialBlockRequestID: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownEditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = font
        textView.isEditable = isEditable
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
        guard let textView = nsView.documentView as? MarkdownEditorTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        applyHighlight(to: textView)
        if commercialBlockRequestID != context.coordinator.lastCommercialBlockRequestID {
            context.coordinator.lastCommercialBlockRequestID = commercialBlockRequestID
            textView.wrapCommercialBlock()
        }
    }

    private func applyHighlight(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        guard let highlightRange,
              highlightRange.location >= 0,
              highlightRange.location + highlightRange.length <= fullRange.length
        else { return }
        layoutManager.addTemporaryAttribute(
            .backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.25),
            forCharacterRange: highlightRange
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: (NSRange, CGRect?) -> Void
        var lastCommercialBlockRequestID = 0

        init(text: Binding<String>, onSelectionChange: @escaping (NSRange, CGRect?) -> Void) {
            self.text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            guard range.length > 0,
                  let layoutManager = tv.layoutManager,
                  let container = tv.textContainer,
                  let scrollView = tv.enclosingScrollView
            else {
                onSelectionChange(range, nil)
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += tv.textContainerInset.width
            rect.origin.y += tv.textContainerInset.height
            let rectInScrollView = tv.convert(rect, to: scrollView)
            onSelectionChange(range, rectInScrollView)
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
            } else if event.modifierFlags.contains(.shift) {
                switch chars {
                case "K", "k": wrapCommercialBlock(); return
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

    /// Wraps the current selection in `[[БЛОК]]`/`[[/БЛОК]]` marker lines,
    /// identifying a commercial block for `CommercialBlockSplitter` at
    /// publish time. Reachable via Cmd+Shift+K or programmatically via
    /// `MarkdownTextEditor.commercialBlockRequestID`.
    func wrapCommercialBlock() {
        wrapSelection(prefix: "[[БЛОК]]\n", suffix: "\n[[/БЛОК]]")
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
