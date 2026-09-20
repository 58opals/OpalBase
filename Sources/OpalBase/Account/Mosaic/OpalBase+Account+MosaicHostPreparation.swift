// OpalBase+Account+MosaicHostPreparation.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    func makeMosaicTransactionHost(
        profile: OpalFusion.Mosaic.Profile,
        network: OpalBase.Network.Environment,
        attemptBinding: MosaicAttemptBinding,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputPlan: OpalBase.Account.MosaicPrivateAlphaRuntime.OutputPlan,
        transactionReader: OpalBase.Network.TransactionReader,
        signingApproval: OpalBase.Account.MosaicPrivateAlphaRuntime.SigningApproval? = nil,
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
            outputPlan: outputPlan,
            transactionPolicy: try .init(
                profile: profile,
                network: network,
                transactionReader: transactionReader
            ),
            attemptJournal: attemptJournal,
            signingApproval: signingApproval
        )
    }

    func makeMosaicPrivateAlphaRecoveryOwner(
        state: MosaicAttemptJournalStore.RecoveryState
    ) throws -> MosaicPrivateAlphaRecoveryOwner {
        try .init(addressBook: addressBook, state: state)
    }
}
#endif
