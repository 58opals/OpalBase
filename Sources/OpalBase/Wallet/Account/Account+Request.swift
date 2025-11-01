// Account+Request.swift

import Foundation

extension Account {
    public enum Request: Hashable, Sendable {
        case broadcast(Transaction.Hash)
        case refreshUnspentTransactionOutputSet
        case calculateBalance
    }
}
