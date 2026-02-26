// AddressModel+BookActor+CoinSelectionModel.swift

import Foundation

// MARK: - Coin Selection
extension AddressModel.BookActor {
    public enum CoinSelectionModel: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll
    }
}

extension AddressModel.BookActor.CoinSelectionModel {
    public enum TokenSelectionPolicy: Sendable {
        case excludeTokenUTXOs
        case allowTokenUTXOs
    }
    
    struct Configuration {
        let recipientOutputs: [TransactionModel.OutputModel]
        let outputsWithChange: [TransactionModel.OutputModel]
        let strategy: AddressModel.BookActor.CoinSelectionModel
        let shouldAllowDustDonation: Bool
        let tokenSelectionPolicy: TokenSelectionPolicy
        
        init(recipientOutputs: [TransactionModel.OutputModel],
             outputsWithChange: [TransactionModel.OutputModel],
             strategy: AddressModel.BookActor.CoinSelectionModel,
             shouldAllowDustDonation: Bool = false,
             tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) {
            self.recipientOutputs = recipientOutputs
            self.outputsWithChange = outputsWithChange
            self.strategy = strategy
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.tokenSelectionPolicy = tokenSelectionPolicy
        }
        
        init(recipientOutputs: [TransactionModel.OutputModel],
             changeLockingScript: Data?,
             strategy: AddressModel.BookActor.CoinSelectionModel = .greedyLargestFirst,
             shouldAllowDustDonation: Bool = false,
             tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) {
            let outputsWithChange: [TransactionModel.OutputModel]
            if let changeLockingScript {
                let changeTemplate = TransactionModel.OutputModel(value: 0, lockingScript: changeLockingScript)
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
        
        static func makeTemplateConfiguration(strategy: AddressModel.BookActor.CoinSelectionModel = .greedyLargestFirst,
                                              shouldAllowDustDonation: Bool = false,
                                              tokenSelectionPolicy: TokenSelectionPolicy = .excludeTokenUTXOs) -> Self {
            Self(recipientOutputs: AddressModel.BookActor.CoinSelectionModel.TemplatesModel.recipientOutputs,
                 outputsWithChange: AddressModel.BookActor.CoinSelectionModel.TemplatesModel.outputsWithChange,
                 strategy: strategy,
                 shouldAllowDustDonation: shouldAllowDustDonation,
                 tokenSelectionPolicy: tokenSelectionPolicy)
        }
    }
    
    struct EvaluationModel {
        let excess: UInt64
    }
    
    enum TemplatesModel {
        static let lockingScript: Data = Data(repeating: 0, count: 25)
        static let recipientOutputs: [TransactionModel.OutputModel] = [TransactionModel.OutputModel(value: 0,
                                                                                lockingScript: lockingScript)]
        static let outputsWithChange: [TransactionModel.OutputModel] = {
            let recipient = TransactionModel.OutputModel(value: 0, lockingScript: lockingScript)
            let change = TransactionModel.OutputModel(value: 0, lockingScript: lockingScript)
            return [recipient, change]
        }()
    }
    
    static func evaluate(configuration: Configuration,
                         total: UInt64,
                         inputCount: Int,
                         targetAmount: UInt64,
                         recipientOutputs: [TransactionModel.OutputModel],
                         outputsWithChange: [TransactionModel.OutputModel],
                         minimumRelayFeeRate: UInt64,
                         feePerByte: UInt64) throws -> EvaluationModel? {
        let changeOutputTemplate: TransactionModel.OutputModel? = outputsWithChange.count > recipientOutputs.count
        ? outputsWithChange.last
        : nil
        let changeDustThreshold = try changeOutputTemplate?.calculateDustThreshold(feeRate: minimumRelayFeeRate) ?? 0
        let feeWithoutChange = try TransactionModel.estimateFee(inputCount: inputCount,
                                                           outputs: recipientOutputs,
                                                           feePerByte: feePerByte)
        let requiredWithoutChange = try targetAmount.addOrThrow(
            feeWithoutChange,
            overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount
        )
        
        if total >= requiredWithoutChange {
            let excess = total - requiredWithoutChange
            if excess == 0 {
                return EvaluationModel(excess: excess)
            }
            if configuration.shouldAllowDustDonation && excess < changeDustThreshold {
                return EvaluationModel(excess: excess)
            }
        }
        
        let feeWithChange = try TransactionModel.estimateFee(inputCount: inputCount,
                                                        outputs: outputsWithChange,
                                                        feePerByte: feePerByte)
        let requiredWithChange = try targetAmount.addOrThrow(
            feeWithChange,
            overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount
        )
        
        guard total >= requiredWithChange else { return nil }
        
        let change = total - requiredWithChange
        guard change == 0 || change >= changeDustThreshold else { return nil }
        
        return EvaluationModel(excess: change)
    }
}
