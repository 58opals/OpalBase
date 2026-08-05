// OpalBase+CashCodeInteractor.swift

public extension OpalBase {
    /// Wallet-facing Cash Code v1 receiver lifecycle façade.
    struct CashCodeInteractor: Sendable {
        private let transport: OpalBase.ReusablePaymentAddress.Transport
        private let persistence: OpalBase.ReusablePaymentAddress.StatePersistence

        public init(
            transport: OpalBase.ReusablePaymentAddress.Transport,
            persistence: OpalBase.ReusablePaymentAddress.StatePersistence
        ) {
            self.transport = transport
            self.persistence = persistence
        }

        /// Opens or creates one exactly bound restoration lifecycle.
        ///
        /// The signing capabilities are retained only by the returned actor and
        /// are never included in its durable state.
        public func openRestoration(
            for address: OpalBase.ReusablePaymentAddress,
            keyOrigin: OpalBase.ReusablePaymentAddress.KeyOrigin,
            restoreStartHeight: UInt,
            scanSigningKey: OpalBase.Key.SigningKey,
            spendSigningKey: OpalBase.Key.SigningKey
        ) async throws -> OpalBase.ReusablePaymentAddress.RestorationActor {
            guard address.profile == .cashCodeV1 else {
                throw OpalBase.ReusablePaymentAddress.Error
                    .unsupportedProfile(address.profile)
            }
            guard scanSigningKey.publicKey == address.scanPublicKey else {
                throw OpalBase.ReusablePaymentAddress.Error
                    .scanSigningKeyMismatch
            }
            guard spendSigningKey.publicKey == address.spendPublicKey else {
                throw OpalBase.ReusablePaymentAddress.Error
                    .spendSigningKeyMismatch
            }

            let state: OpalBase.ReusablePaymentAddress.RestorationState
            if let persisted = try await persistence.loadState() {
                try persisted.requireBinding(
                    address: address,
                    keyOrigin: keyOrigin,
                    restoreStartHeight: restoreStartHeight
                )
                try persisted.requireCapabilities(
                    scanSigningKey: scanSigningKey,
                    spendSigningKey: spendSigningKey
                )
                state = persisted
            } else {
                let initial = OpalBase.ReusablePaymentAddress.RestorationState(
                    revision: 1,
                    address: address,
                    keyOrigin: keyOrigin,
                    restoreStartHeight: restoreStartHeight,
                    nextUnscannedHeight: restoreStartHeight
                )
                try initial.validate()
                try initial.requireCapabilities(
                    scanSigningKey: scanSigningKey,
                    spendSigningKey: spendSigningKey
                )
                try await persistence.saveState(
                    initial,
                    replacingRevision: nil
                )
                state = initial
            }

            return OpalBase.ReusablePaymentAddress.RestorationActor(
                address: address,
                transport: transport,
                persistence: persistence,
                scanSigningKey: scanSigningKey,
                spendSigningKey: spendSigningKey,
                state: state
            )
        }
    }
}
