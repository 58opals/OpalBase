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
    struct Evaluation {
        let excess: UInt64
    }
    
    enum Templates {
        static var lockingScript: Data { Data(repeating: 0, count: 25) }
        
        static var recipientOutputs: [Transaction.Output] {
            [Transaction.Output(value: 0, lockingScript: lockingScript)]
        }
        
        static var outputsWithChange: [Transaction.Output] {
            let recipient = Transaction.Output(value: 0, lockingScript: lockingScript)
            let change = Transaction.Output(value: 0, lockingScript: lockingScript)
            return [recipient, change]
        }
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
