// OpalBase+Account+MosaicTransactionPolicy.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    /// Type-erases a transaction-profile validator for the one-attempt wallet host.
    struct MosaicTransactionPolicy: Sendable {
        private let validation: @Sendable (
            OpalBase.Transaction,
            OpalFusion.Host.MosaicTransactionSigningRequest,
            UInt64
        ) async throws -> Void

        init(
            validation: @escaping @Sendable (
                OpalBase.Transaction,
                OpalFusion.Host.MosaicTransactionSigningRequest,
                UInt64
            ) async throws -> Void
        ) {
            self.validation = validation
        }

        func validate(
            transaction: OpalBase.Transaction,
            request: OpalFusion.Host.MosaicTransactionSigningRequest,
            feeSatoshis: UInt64
        ) async throws {
            try await validation(transaction, request, feeSatoshis)
        }

        static func opalV0(
            network: OpalBase.Network.Environment,
            transactionReader: OpalBase.Network.TransactionReader
        ) throws -> Self {
            let policy = try MosaicV0TransactionPolicy(
                network: network,
                transactionReader: transactionReader
            )
            return .init { transaction, request, feeSatoshis in
                try await policy.validate(
                    transaction: transaction,
                    request: request,
                    feeSatoshis: feeSatoshis
                )
            }
        }
    }
}
#endif
