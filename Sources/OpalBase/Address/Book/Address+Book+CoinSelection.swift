// Address+Book+CoinSelection.swift

import Foundation

extension Address.Book {
    public enum CoinSelection: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll
    }
}

extension Address.Book.CoinSelection {
    struct Configuration {
        let recipientOutputs: [Transaction.Output]
        let outputsWithChange: [Transaction.Output]
        let strategy: Address.Book.CoinSelection
        
        init(recipientOutputs: [Transaction.Output],
             outputsWithChange: [Transaction.Output],
             strategy: Address.Book.CoinSelection) {
            self.recipientOutputs = recipientOutputs
            self.outputsWithChange = outputsWithChange
            self.strategy = strategy
        }
        
        init(recipientOutputs: [Transaction.Output],
             changeLockingScript: Data?,
             strategy: Address.Book.CoinSelection = .greedyLargestFirst) {
            let outputsWithChange: [Transaction.Output]
            if let changeLockingScript {
                let changeTemplate = Transaction.Output(value: 0, lockingScript: changeLockingScript)
                outputsWithChange = recipientOutputs + [changeTemplate]
            } else {
                outputsWithChange = recipientOutputs
            }
            
            self.init(recipientOutputs: recipientOutputs,
                      outputsWithChange: outputsWithChange,
                      strategy: strategy)
        }
        
        static func makeTemplateConfiguration(strategy: Address.Book.CoinSelection = .greedyLargestFirst) -> Self {
            Self(recipientOutputs: Address.Book.CoinSelection.Templates.recipientOutputs,
                 outputsWithChange: Address.Book.CoinSelection.Templates.outputsWithChange,
                 strategy: strategy)
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
    
    static func evaluate(total: UInt64,
                         inputCount: Int,
                         targetAmount: UInt64,
                         recipientOutputs: [Transaction.Output],
                         outputsWithChange: [Transaction.Output],
                         dustLimit: UInt64,
                         feePerByte: UInt64) -> Evaluation? {
        let feeWithoutChange = Transaction.estimateFee(inputCount: inputCount,
                                                       outputs: recipientOutputs,
                                                       feePerByte: feePerByte)
        let requiredWithoutChange = targetAmount &+ feeWithoutChange
        
        if total >= requiredWithoutChange {
            let excess = total &- requiredWithoutChange
            if excess == 0 || excess < dustLimit {
                return Evaluation(excess: excess)
            }
        }
        
        let feeWithChange = Transaction.estimateFee(inputCount: inputCount,
                                                    outputs: outputsWithChange,
                                                    feePerByte: feePerByte)
        let requiredWithChange = targetAmount &+ feeWithChange
        
        guard total >= requiredWithChange else { return nil }
        
        let change = total &- requiredWithChange
        guard change == 0 || change >= dustLimit else { return nil }
        
        return Evaluation(excess: change)
    }
}
