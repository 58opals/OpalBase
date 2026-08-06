// OpalBase+Account+MosaicHostPreparation.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    func makeMosaicTransactionHost(
        network: OpalBase.Network.Environment,
        generation: UInt64,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionPolicy: MosaicTransactionPolicy
    ) throws -> MosaicTransactionHostActor {
        try requirePrivateKeyMaterial()
        return try MosaicTransactionHostActor(
            addressBook: addressBook,
            network: network,
            generation: generation,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis,
            transactionPolicy: transactionPolicy
        )
    }
}
#endif
