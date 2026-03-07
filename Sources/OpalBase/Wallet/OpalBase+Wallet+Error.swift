// OpalBase+Wallet+Error.swift

import Foundation

extension _OpalBase.Wallet {
    public enum Error: Swift.Error, Equatable {
        case snapshotDoesNotMatchWallet
        case cannotFetchAccount(index: UInt32)
    }
}
