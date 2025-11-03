// Address+Book+CoinSelector.swift

import Foundation

extension Address.Book {
    struct CoinSelector {
        let utxos: [Transaction.Output.Unspent]
        let configuration: Address.Book.CoinSelection.Configuration
        let targetAmount: UInt64
        let feePerByte: UInt64
        let dustLimit: UInt64
        
        init(utxos: [Transaction.Output.Unspent],
             configuration: Address.Book.CoinSelection.Configuration,
             targetAmount: UInt64,
             feePerByte: UInt64,
             dustLimit: UInt64) {
            self.utxos = utxos
            self.configuration = configuration
            self.targetAmount = targetAmount
            self.feePerByte = feePerByte
            self.dustLimit = dustLimit
        }
    }
}

extension Address.Book {
    public enum CoinSelection: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll
    }
}

extension Address.Book.CoinSelector {
    func select() throws -> [Transaction.Output.Unspent] {
        switch configuration.strategy {
        case .greedyLargestFirst:
            return try selectGreedy()
        case .branchAndBound:
            return try selectBranchAndBound()
        case .sweepAll:
            return utxos
        }
    }
    
    private func selectGreedy() throws -> [Transaction.Output.Unspent] {
        var selection: [Transaction.Output.Unspent] = .init()
        var total: UInt64 = 0
        
        for utxo in utxos {
            selection.append(utxo)
            total &+= utxo.value
            
            if evaluate(selection: selection, sum: total) != nil {
                return selection
            }
        }
        
        throw Address.Book.Error.insufficientFunds
    }
    
    private func selectBranchAndBound() throws -> [Transaction.Output.Unspent] {
        var bestSelection: [Transaction.Output.Unspent] = .init()
        var bestEvaluation: Address.Book.CoinSelection.Evaluation?
        let suffixTotals = makeSuffixTotals()
        
        func updateBest(selection: [Transaction.Output.Unspent], sum: UInt64) {
            guard let evaluation = evaluate(selection: selection, sum: sum) else { return }
            
            if let currentBest = bestEvaluation {
                if evaluation.excess < currentBest.excess {
                    bestEvaluation = evaluation
                    bestSelection = selection
                } else if evaluation.excess == currentBest.excess,
                          selection.count < bestSelection.count {
                    bestEvaluation = evaluation
                    bestSelection = selection
                }
            } else {
                bestEvaluation = evaluation
                bestSelection = selection
            }
        }
        
        func explore(index: Int, selection: [Transaction.Output.Unspent], sum: UInt64) {
            updateBest(selection: selection, sum: sum)
            
            guard index < utxos.count else { return }
            
            let remaining = suffixTotals[index]
            let minimalFee = Transaction.estimateFee(inputCount: selection.count,
                                                     outputs: configuration.recipientOutputs,
                                                     feePerByte: feePerByte)
            let minimalRequirement = targetAmount &+ minimalFee
            if sum &+ remaining < minimalRequirement { return }
            
            var selectionIncludingCurrent = selection
            selectionIncludingCurrent.append(utxos[index])
            let sumIncludingCurrent = sum &+ utxos[index].value
            
            explore(index: index + 1,
                    selection: selectionIncludingCurrent,
                    sum: sumIncludingCurrent)
            explore(index: index + 1, selection: selection, sum: sum)
        }
        
        explore(index: 0, selection: .init(), sum: 0)
        guard !bestSelection.isEmpty else { throw Address.Book.Error.insufficientFunds }
        return bestSelection
    }
    
    private func evaluate(selection: [Transaction.Output.Unspent],
                          sum: UInt64) -> Address.Book.CoinSelection.Evaluation? {
        Address.Book.CoinSelection.evaluate(total: sum,
                                            inputCount: selection.count,
                                            targetAmount: targetAmount,
                                            recipientOutputs: configuration.recipientOutputs,
                                            outputsWithChange: configuration.outputsWithChange,
                                            dustLimit: dustLimit,
                                            feePerByte: feePerByte)
    }
    
    private func makeSuffixTotals() -> [UInt64] {
        guard !utxos.isEmpty else { return [0] }
        
        var suffixTotals: [UInt64] = Array(repeating: 0, count: utxos.count + 1)
        for index in stride(from: utxos.count - 1, through: 0, by: -1) {
            suffixTotals[index] = suffixTotals[index + 1] &+ utxos[index].value
        }
        
        return suffixTotals
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
