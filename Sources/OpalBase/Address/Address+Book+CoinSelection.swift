// Address+Book+CoinSelection.swift

import Foundation

// MARK: - Coin Selection
extension Address.Book {
    public enum CoinSelection: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll
    }
}

extension Address.Book.CoinSelection {
    public enum TokenSelectionPolicy: Sendable {
        case excludeTokenUTXOs
        case allowTokenUTXOs
    }
    
    struct Configuration {
        let recipientOutputs: [Transaction.Output]
        let outputsWithChange: [Transaction.Output]
        let strategy: Address.Book.CoinSelection
        let shouldAllowDustDonation: Bool
        let tokenSelectionPolicy: TokenSelectionPolicy
        
        init(recipientOutputs: [Transaction.Output],
             outputsWithChange: [Transaction.Output],
             strategy: Address.Book.CoinSelection,
             shouldAllowDustDonation: Bool = false,
             tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) {
            self.recipientOutputs = recipientOutputs
            self.outputsWithChange = outputsWithChange
            self.strategy = strategy
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.tokenSelectionPolicy = tokenSelectionPolicy
        }
        
        init(recipientOutputs: [Transaction.Output],
             changeLockingScript: Data?,
             strategy: Address.Book.CoinSelection = .greedyLargestFirst,
             shouldAllowDustDonation: Bool = false,
             tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) {
            let outputsWithChange: [Transaction.Output]
            if let changeLockingScript {
                let changeTemplate = Transaction.Output(value: 0, lockingScript: changeLockingScript)
                outputsWithChange = recipientOutputs + [changeTemplate]
            } else {
                outputsWithChange = recipientOutputs
            }
            
            self.init(recipientOutputs: recipientOutputs,
                      outputsWithChange: outputsWithChange,
                      strategy: strategy,
                      shouldAllowDustDonation: shouldAllowDustDonation,
                      tokenSelectionPolicy: tokenSelectionPolicy)
        }
        
        static func makeTemplateConfiguration(strategy: Address.Book.CoinSelection = .greedyLargestFirst,
                                              shouldAllowDustDonation: Bool = false,
                                              tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) -> Self {
            Self(recipientOutputs: Address.Book.CoinSelection.Templates.recipientOutputs,
                 outputsWithChange: Address.Book.CoinSelection.Templates.outputsWithChange,
                 strategy: strategy,
                 shouldAllowDustDonation: shouldAllowDustDonation,
                 tokenSelectionPolicy: tokenSelectionPolicy)
        }
    }
    
    struct Evaluation {
        let excess: UInt64
    }
    
    enum Templates {
        static let lockingScript: Data = Data(repeating: 0, count: 25)
        static let recipientOutputs: [Transaction.Output] = [Transaction.Output(value: 0,
                                                                                lockingScript: lockingScript)]
        static let outputsWithChange: [Transaction.Output] = {
            let recipient = Transaction.Output(value: 0, lockingScript: lockingScript)
            let change = Transaction.Output(value: 0, lockingScript: lockingScript)
            return [recipient, change]
        }()
    }
    
    static func evaluate(configuration: Configuration,
                         total: UInt64,
                         inputCount: Int,
                         targetAmount: UInt64,
                         recipientOutputs: [Transaction.Output],
                         outputsWithChange: [Transaction.Output],
                         minimumRelayFeeRate: UInt64,
                         feePerByte: UInt64) throws -> Evaluation? {
        let changeOutputTemplate: Transaction.Output? = outputsWithChange.count > recipientOutputs.count
        ? outputsWithChange.last
        : nil
        let changeDustThreshold = try changeOutputTemplate?.calculateDustThreshold(feeRate: minimumRelayFeeRate) ?? 0
        let feeWithoutChange = try Transaction.estimateFee(inputCount: inputCount,
                                                           outputs: recipientOutputs,
                                                           feePerByte: feePerByte)
        let requiredWithoutChange = try targetAmount.addOrThrow(
            feeWithoutChange,
            overflowError: Address.Book.Error.paymentExceedsMaximumAmount
        )
        
        if total >= requiredWithoutChange {
            let excess = total - requiredWithoutChange
            if excess == 0 {
                return Evaluation(excess: excess)
            }
            if configuration.shouldAllowDustDonation && excess < changeDustThreshold {
                return Evaluation(excess: excess)
            }
        }
        
        let feeWithChange = try Transaction.estimateFee(inputCount: inputCount,
                                                        outputs: outputsWithChange,
                                                        feePerByte: feePerByte)
        let requiredWithChange = try targetAmount.addOrThrow(
            feeWithChange,
            overflowError: Address.Book.Error.paymentExceedsMaximumAmount
        )
        
        guard total >= requiredWithChange else { return nil }
        
        let change = total - requiredWithChange
        guard change == 0 || change >= changeDustThreshold else { return nil }
        
        return Evaluation(excess: change)
    }
}
