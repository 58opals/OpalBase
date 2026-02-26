// AccountActor+Request.swift

import Foundation

extension AccountActor {
    enum Request: Hashable, Sendable {
        case broadcast(TransactionModel.HashModel)
        case refreshUTXOSet
        case calculateBalance
    }
}
