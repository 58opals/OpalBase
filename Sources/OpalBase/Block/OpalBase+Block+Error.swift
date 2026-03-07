// OpalBase+Block+Error.swift

import Foundation

extension _OpalBase.Block {
    enum Error: Swift.Error {
        case transactionCountOverflow(UInt64)
    }
}
