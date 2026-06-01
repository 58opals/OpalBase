// OpalBase+Account+CashFusionTransactionAssembler+Outpoint.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.CashFusionTransactionAssembler {
    struct Outpoint: Hashable, Sendable {
        let transactionHash: OpalBase.Transaction.Hash
        let outputIndex: UInt32

        init(_ input: OpalBase.Transaction.Input) {
            self.transactionHash = input.previousTransactionHash
            self.outputIndex = input.previousTransactionOutputIndex
        }

        init(_ unspentOutput: OpalBase.Transaction.Output.Unspent) {
            self.transactionHash = unspentOutput.previousTransactionHash
            self.outputIndex = unspentOutput.previousTransactionOutputIndex
        }
    }
}
#endif
