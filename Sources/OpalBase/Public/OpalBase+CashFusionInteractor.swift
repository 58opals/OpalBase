// OpalBase+CashFusionInteractor.swift

#if os(macOS)
public extension OpalBase {
    /// CashFusion lane for session lifecycle and coordinator state using explicit wallet-owned private account authority.
    struct CashFusionInteractor: Sendable {
        private let privateAccount: OpalBase.Account

        public init(privateAccount: OpalBase.Account) {
            self.privateAccount = privateAccount
        }

        public func evaluateReadiness() async throws -> OpalBase.Account.CashFusionReadiness {
            try await privateAccount.evaluateCashFusionReadiness()
        }

        public func prepareSession(
            configuration: OpalBase.Account.CashFusionSession.Configuration,
            request: OpalBase.Account.CashFusionRequest
        ) async throws -> OpalBase.Account.CashFusionSession {
            try await privateAccount.prepareCashFusionSession(
                configuration: configuration,
                request: request
            )
        }
    }
}
#endif
