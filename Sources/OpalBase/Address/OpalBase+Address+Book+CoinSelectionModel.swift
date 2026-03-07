// OpalBase+Address+Book+CoinSelectionModel.swift

import Foundation

// MARK: - Coin Selection
extension _OpalBase.Address.Book {
    public enum CoinSelectionModel: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll
    }
}

extension _OpalBase.Address.Book.CoinSelectionModel {
    public enum TokenSelectionPolicy: Sendable {
        case excludeTokenUTXOs
        case allowTokenUTXOs
    }
    
    struct Configuration {
        let recipientOutputs: [OpalBase.Transaction.OutputModel]
        let outputsWithChange: [OpalBase.Transaction.OutputModel]
        let strategy: OpalBase.Address.Book.CoinSelectionModel
        let shouldAllowDustDonation: Bool
        let tokenSelectionPolicy: TokenSelectionPolicy
        
        init(recipientOutputs: [OpalBase.Transaction.OutputModel],
             outputsWithChange: [OpalBase.Transaction.OutputModel],
             strategy: OpalBase.Address.Book.CoinSelectionModel,
             shouldAllowDustDonation: Bool = false,
             tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) {
            self.recipientOutputs = recipientOutputs
            self.outputsWithChange = outputsWithChange
            self.strategy = strategy
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.tokenSelectionPolicy = tokenSelectionPolicy
        }
        
        init(recipientOutputs: [OpalBase.Transaction.OutputModel],
             changeLockingScript: Data?,
             strategy: OpalBase.Address.Book.CoinSelectionModel = .greedyLargestFirst,
             shouldAllowDustDonation: Bool = false,
             tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) {
            let outputsWithChange: [OpalBase.Transaction.OutputModel]
            if let changeLockingScript {
                let changeTemplate = OpalBase.Transaction.OutputModel(value: 0, lockingScript: changeLockingScript)
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
        
        static func makeTemplateConfiguration(strategy: OpalBase.Address.Book.CoinSelectionModel = .greedyLargestFirst,
                                              shouldAllowDustDonation: Bool = false,
                                              tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) -> Self {
            Self(recipientOutputs: OpalBase.Address.Book.CoinSelectionModel.Templates.recipientOutputs,
                 outputsWithChange: OpalBase.Address.Book.CoinSelectionModel.Templates.outputsWithChange,
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
        static let recipientOutputs: [OpalBase.Transaction.OutputModel] = [OpalBase.Transaction.OutputModel(value: 0,
                                                                                lockingScript: lockingScript)]
        static let outputsWithChange: [OpalBase.Transaction.OutputModel] = {
            let recipient = OpalBase.Transaction.OutputModel(value: 0, lockingScript: lockingScript)
            let change = OpalBase.Transaction.OutputModel(value: 0, lockingScript: lockingScript)
            return [recipient, change]
        }()
    }
    
    static func evaluate(configuration: Configuration,
                         total: UInt64,
                         inputCount: Int,
                         targetAmount: UInt64,
                         recipientOutputs: [OpalBase.Transaction.OutputModel],
                         outputsWithChange: [OpalBase.Transaction.OutputModel],
                         minimumRelayFeeRate: UInt64,
                         feePerByte: UInt64) throws -> Evaluation? {
        let changeOutputTemplate: OpalBase.Transaction.OutputModel? = outputsWithChange.count > recipientOutputs.count
        ? outputsWithChange.last
        : nil
        let changeDustThreshold = try changeOutputTemplate?.calculateDustThreshold(feeRate: minimumRelayFeeRate) ?? 0
        let feeWithoutChange = try OpalBase.Transaction.estimateFee(inputCount: inputCount,
                                                           outputs: recipientOutputs,
                                                           feePerByte: feePerByte)
        let requiredWithoutChange = try targetAmount.addOrThrow(
            feeWithoutChange,
            overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
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
        
        let feeWithChange = try OpalBase.Transaction.estimateFee(inputCount: inputCount,
                                                        outputs: outputsWithChange,
                                                        feePerByte: feePerByte)
        let requiredWithChange = try targetAmount.addOrThrow(
            feeWithChange,
            overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
        )
        
        guard total >= requiredWithChange else { return nil }
        
        let change = total - requiredWithChange
        guard change == 0 || change >= changeDustThreshold else { return nil }
        
        return Evaluation(excess: change)
    }
}
