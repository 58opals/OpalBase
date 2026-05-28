// OpalBase+Block+Error.swift

import Foundation

extension _OpalBase.Block {
    enum Error: Swift.Error {
        case emptyTransactionList
        case invalidPreviousBlockHashLength(expected: Int, actual: Int)
        case invalidMerkleRootLength(expected: Int, actual: Int)
        case transactionCountOverflow(UInt64)
    }
}

extension _OpalBase.Block.Error: Equatable {}
