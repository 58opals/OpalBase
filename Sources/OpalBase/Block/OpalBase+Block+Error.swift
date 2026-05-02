// OpalBase+Block+Error.swift

import Foundation

extension _OpalBase.Block {
    enum Error: Swift.Error {
        case emptyTransactionList
        case transactionCountOverflow(UInt64)
    }
}

extension _OpalBase.Block.Error: Equatable {}
