// OpalBase+Storage+PersistenceOperationCoordinator.swift

extension _OpalBase.Storage {
    actor PersistenceOperationCoordinator {
        // Persistence intentionally serializes process-wide so independently
        // constructed storage, snapshot, and mnemonic facades coordinate.
        static let processWideCoordinator = PersistenceOperationCoordinator()

        // Actor methods can reenter while awaiting backend work, so this queue
        // extends exclusivity across the complete asynchronous operation.
        private var isOperationActive = false
        private var operationWaiters: [CheckedContinuation<Void, Never>] = .init()

        func performExclusively<Result: Sendable>(
            _ operation: @Sendable () async throws -> Result
        ) async rethrows -> Result {
            await acquireOperationAccess()
            defer { releaseOperationAccess() }
            return try await operation()
        }

        private func acquireOperationAccess() async {
            guard isOperationActive else {
                isOperationActive = true
                return
            }

            await withCheckedContinuation { continuation in
                operationWaiters.append(continuation)
            }
        }

        private func releaseOperationAccess() {
            guard !operationWaiters.isEmpty else {
                isOperationActive = false
                return
            }

            operationWaiters.removeFirst().resume()
        }
    }
}
