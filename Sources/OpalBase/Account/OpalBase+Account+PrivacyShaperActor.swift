// OpalBase+Account+PrivacyShaperActor.swift

import Foundation

extension _OpalBase.Account {
    actor PrivacyShaperActor {
        private let configuration: Configuration
        private var generator = SystemRandomNumberGenerator()

        init(configuration: Configuration) {
            self.configuration = configuration
        }
    }
}

extension _OpalBase.Account.PrivacyShaperActor {
    func applyCoinSelectionHeuristics(to utxos: [OpalBase.Transaction.Output.Unspent]) -> [OpalBase.Transaction.Output.Unspent] {
        guard configuration.shouldRandomizeUTXOOrdering, utxos.count > 1 else { return utxos }
        return utxos.shuffled(using: &generator)
    }
    
    func organizeOutputs(_ outputs: [OpalBase.Transaction.Output]) throws -> [OpalBase.Transaction.Output] {
        guard outputs.count > 1 else { return outputs }
        
        if configuration.shouldRandomizeRecipientOrdering {
            return outputs.shuffled(using: &generator)
        }
        
        return try OpalBase.Transaction.Output.applyBIP69Ordering(outputs)
    }
}
