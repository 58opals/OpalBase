// Account+Request.swift

import Foundation

extension Account {
    enum Request: Hashable, Sendable {
        case broadcast(Transaction.Hash)
        case refreshUTXOSet
    }
}
