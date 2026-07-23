import Foundation

enum SemanticCollectionDeadline {
    struct DeadlineError: Error, LocalizedError, Equatable {
        var errorDescription: String? {
            "Сбор остановлен: прошло 10 минут. Семантика темы не изменена."
        }
    }

    static func run<T: Sendable>(
        timeout: Duration,
        operation: @escaping @MainActor @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DeadlineError()
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }
}
