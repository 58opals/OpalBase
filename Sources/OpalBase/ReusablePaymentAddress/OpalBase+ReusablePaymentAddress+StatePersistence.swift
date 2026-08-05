// OpalBase+ReusablePaymentAddress+StatePersistence.swift

extension _OpalBase.ReusablePaymentAddress {
    /// Atomic durable-state operations for one Cash Code registration.
    ///
    /// `saveState` must replace the complete state atomically and reject a
    /// mismatched prior revision with `Error.stateRevisionConflict`.
    public struct StatePersistence: Sendable {
        private let stateLoader: @Sendable () async throws -> RestorationState?
        private let stateSaver: @Sendable (
            RestorationState,
            UInt64?
        ) async throws -> Void

        public init(
            loadState: @escaping @Sendable () async throws -> RestorationState?,
            saveState: @escaping @Sendable (
                RestorationState,
                UInt64?
            ) async throws -> Void
        ) {
            self.stateLoader = loadState
            self.stateSaver = saveState
        }

        public func loadState() async throws -> RestorationState? {
            try await stateLoader()
        }

        public func saveState(
            _ state: RestorationState,
            replacingRevision expectedRevision: UInt64?
        ) async throws {
            try await stateSaver(state, expectedRevision)
        }
    }
}
