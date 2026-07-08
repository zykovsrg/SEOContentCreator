import SwiftUI
import AppKit

struct PromptTemplateTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var insertionToken: String
    var insertionRequestID: Int

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTemplateNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 18, height: 18)
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

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTemplateNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        applyVariableHighlight(to: textView)
        guard insertionRequestID != context.coordinator.lastInsertionRequestID,
              !insertionToken.isEmpty
        else { return }
        context.coordinator.lastInsertionRequestID = insertionRequestID
        let result = PromptVariableInsertion.insert(insertionToken, into: textView.string, selectedRange: textView.selectedRange())
        textView.string = result.text
        textView.setSelectedRange(result.selectedRange)
        text = result.text
        selectedRange = result.selectedRange
        applyVariableHighlight(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    private func applyVariableHighlight(to textView: NSTextView) {
        guard let layoutManager = textView.layoutManager else { return }
        let ns = textView.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

        let regex = try? NSRegularExpression(pattern: #"\{\{[^}]+\}\}"#)
        regex?.enumerateMatches(in: textView.string, range: full) { match, _, _ in
            guard let range = match?.range else { return }
            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemTeal.withAlphaComponent(0.16), forCharacterRange: range)
            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.systemTeal, forCharacterRange: range)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var selectedRange: Binding<NSRange>
        var lastInsertionRequestID = 0

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            self.text = text
            self.selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectedRange.wrappedValue = textView.selectedRange()
        }
    }
}

final class PromptTemplateNSTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "s" {
            window?.makeFirstResponder(nil)
            return
        }
        super.keyDown(with: event)
    }
}
