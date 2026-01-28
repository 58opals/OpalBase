// Transaction~BCHChange.swift

import Foundation

extension Transaction {
    func findBitcoinCashChange(for entry: Address.Book.Entry) throws -> Account.SpendPlan.TransactionResult.Change? {
        let lockingScript = entry.address.lockingScript.data
        guard let output = outputs.first(where: { output in
            output.lockingScript == lockingScript
            && output.tokenData == nil
            && output.value > 0
        }) else {
            return nil
        }
        
        return .init(entry: entry, amount: try Satoshi(output.value))
    }
}
