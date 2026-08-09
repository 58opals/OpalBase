// OpalBase+Account+MosaicTransactionPolicy.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    /// Type-erases a transaction-profile validator for the one-attempt wallet host.
    struct MosaicTransactionPolicy: Sendable {
        let profile: OpalFusion.Mosaic.Profile
        let network: OpalBase.Network.Environment
        private let validation: @Sendable (
            OpalBase.Transaction,
            OpalFusion.Host.MosaicTransactionSigningRequest,
            UInt64
        ) async throws -> Void

        init(
            profile: OpalFusion.Mosaic.Profile = .opalV0,
            network: OpalBase.Network.Environment = .chipnet,
            validation: @escaping @Sendable (
                OpalBase.Transaction,
                OpalFusion.Host.MosaicTransactionSigningRequest,
                UInt64
            ) async throws -> Void
        ) {
            self.profile = profile
            self.network = network
            self.validation = validation
        }

        init(
            profile: OpalFusion.Mosaic.Profile,
            network: OpalBase.Network.Environment,
            transactionReader: OpalBase.Network.TransactionReader
        ) throws {
            let policy = try MosaicProfileTransactionPolicy(
                profile: profile,
                network: network,
                transactionReader: transactionReader
            )
            self.init(
                profile: profile,
                network: network
            ) { transaction, request, feeSatoshis in
                try await policy.validate(
                    transaction: transaction,
                    request: request,
                    feeSatoshis: feeSatoshis
                )
            }
        }

        func validate(
            transaction: OpalBase.Transaction,
            request: OpalFusion.Host.MosaicTransactionSigningRequest,
            feeSatoshis: UInt64
        ) async throws {
            try await validation(transaction, request, feeSatoshis)
        }
    }
}
#endif
