// OpalBase+Account+CashFusionRequest.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    public struct CashFusionRequest: Sendable, Equatable {
        public enum OutputPolicy: Sendable, Equatable {
            case explicitAmounts([OpalBase.Satoshi])
            case valuePreserving
        }

        public let selectedInputs: [OpalBase.Transaction.Output.Unspent]
        public let outputAmounts: [OpalBase.Satoshi]
        public let outputPolicy: OutputPolicy

        public init(
            selectedInputs: [OpalBase.Transaction.Output.Unspent],
            outputAmounts: [OpalBase.Satoshi]
        ) {
            self.selectedInputs = selectedInputs
            self.outputAmounts = outputAmounts
            self.outputPolicy = .explicitAmounts(outputAmounts)
        }

        public init(
            selectedInputs: [OpalBase.Transaction.Output.Unspent],
            outputPolicy: OutputPolicy
        ) {
            self.selectedInputs = selectedInputs
            self.outputPolicy = outputPolicy

            switch outputPolicy {
            case .explicitAmounts(let outputAmounts):
                self.outputAmounts = outputAmounts
            case .valuePreserving:
                self.outputAmounts = []
            }
        }
    }
}
#endif
