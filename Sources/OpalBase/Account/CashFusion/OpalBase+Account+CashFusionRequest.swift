// OpalBase+Account+CashFusionRequest.swift

import Foundation

extension _OpalBase.Account {
    public struct CashFusionRequest: Sendable, Equatable {
        public let selectedInputs: [OpalBase.Transaction.Output.Unspent]
        public let outputAmounts: [OpalBase.Satoshi]

        public init(
            selectedInputs: [OpalBase.Transaction.Output.Unspent],
            outputAmounts: [OpalBase.Satoshi]
        ) {
            self.selectedInputs = selectedInputs
            self.outputAmounts = outputAmounts
        }
    }
}
