// OpalBase+Account+MosaicHostPreparation.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    func makeMosaicTransactionHost(
        profile: OpalFusion.Mosaic.Profile,
        network: OpalBase.Network.Environment,
        attemptBinding: MosaicAttemptBinding,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionReader: OpalBase.Network.TransactionReader,
        freshAttempt: consuming MosaicAttemptJournalStore.FreshAttempt
    ) async throws -> MosaicTransactionHostActor {
        try requirePrivateKeyMaterial()
        let attemptJournal = freshAttempt.claimJournal()
        try await attemptJournal.append(.attemptBinding(attemptBinding))
        return try MosaicTransactionHostActor(
            addressBook: addressBook,
            profile: profile,
            network: network,
            attemptBinding: attemptBinding,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis,
            transactionPolicy: try .init(
                profile: profile,
                network: network,
                transactionReader: transactionReader
            ),
            attemptJournal: attemptJournal
        )
    }

    func makeMosaicPrivateAlphaRecoveryOwner(
        state: MosaicAttemptJournalStore.RecoveryState
    ) throws -> MosaicPrivateAlphaRecoveryOwner {
        try .init(addressBook: addressBook, state: state)
    }
}
#endif
