// OpalBase+Account+Request.swift

import Foundation

extension _OpalBase.Account {
    enum Request: Hashable, Sendable {
        case broadcast(OpalBase.Transaction.Hash)
        case refreshUTXOSet
        case calculateBalance
    }
}
