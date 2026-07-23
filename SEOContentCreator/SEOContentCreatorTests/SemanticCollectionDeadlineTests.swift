import Testing
@testable import SEOContentCreator

struct SemanticCollectionDeadlineTests {
    @Test func returnsSuccessfulOperationBeforeDeadline() async throws {
        let value = try await SemanticCollectionDeadline.run(timeout: .seconds(1)) {
            42
        }

        #expect(value == 42)
    }

    @Test func throwsClearErrorAndCancelsSlowOperation() async {
        await #expect(throws: SemanticCollectionDeadline.DeadlineError.self) {
            try await SemanticCollectionDeadline.run(timeout: .milliseconds(10)) {
                try await Task.sleep(for: .seconds(30))
                return 42
            }
        }
    }
}
