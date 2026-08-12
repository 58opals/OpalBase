// OpalBase+Account+MosaicHostPreparation.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    func makeMosaicTransactionHost(
        profile: OpalFusion.Mosaic.Profile,
        network: OpalBase.Network.Environment,
        generation: UInt64,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionReader: OpalBase.Network.TransactionReader,
        freshAttempt: consuming MosaicAttemptJournalStore.FreshAttempt
    ) throws -> MosaicTransactionHostActor {
        try requirePrivateKeyMaterial()
        return try MosaicTransactionHostActor(
            addressBook: addressBook,
            profile: profile,
            network: network,
            generation: generation,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis,
            transactionPolicy: try .init(
                profile: profile,
                network: network,
                transactionReader: transactionReader
            ),
            freshAttempt: freshAttempt
        )
    }
}
#endif
