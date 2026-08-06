// OpalBase+Account+MosaicTransactionPolicy.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    /// Supplies transaction-profile checks that remain unresolved by the Mosaic draft.
    ///
    /// A live adapter must validate fee allocation, remote previous outputs, and the
    /// complete draft transaction profile here before the host can sign.
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
    }
}
#endif
