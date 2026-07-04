import Testing
import Foundation
@testable import SEOContentCreator

struct EditorSessionStateTests {
    private let sampleRange = NSRange(location: 0, length: 5)

    @Test func editingIsEditable() {
        #expect(EditorSessionState.editing.isTextEditable == true)
    }

    @Test func generatingIsNotEditable() {
        #expect(EditorSessionState.generating(range: sampleRange).isTextEditable == false)
    }

    @Test func reviewingIsNotEditable() {
        #expect(EditorSessionState.reviewing(range: sampleRange, proposedText: "x").isTextEditable == false)
    }

    @Test func generatingReportsIsGenerating() {
        #expect(EditorSessionState.generating(range: sampleRange).isGenerating == true)
        #expect(EditorSessionState.editing.isGenerating == false)
        #expect(EditorSessionState.reviewing(range: sampleRange, proposedText: "x").isGenerating == false)
    }

    @Test func canTriggerRegenerateOnlyWhenEditingAndSelectionNonEmpty() {
        #expect(EditorSessionState.canTriggerRegenerate(state: .editing, hasNonEmptySelection: true) == true)
        #expect(EditorSessionState.canTriggerRegenerate(state: .editing, hasNonEmptySelection: false) == false)
        #expect(EditorSessionState.canTriggerRegenerate(state: .generating(range: sampleRange), hasNonEmptySelection: true) == false)
        #expect(EditorSessionState.canTriggerRegenerate(state: .reviewing(range: sampleRange, proposedText: "x"), hasNonEmptySelection: true) == false)
    }

    @Test func canCloseSheetOnlyWhenEditing() {
        #expect(EditorSessionState.canCloseSheet(state: .editing) == true)
        #expect(EditorSessionState.canCloseSheet(state: .generating(range: sampleRange)) == false)
        #expect(EditorSessionState.canCloseSheet(state: .reviewing(range: sampleRange, proposedText: "x")) == false)
    }
}
