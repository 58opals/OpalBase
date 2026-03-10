// OpalBase+Wallet+Error.swift

import Foundation

extension _OpalBase.Wallet {
    public enum Error: Swift.Error, Equatable {
        case snapshotDoesNotMatchWallet
        case accountAlreadyExists(index: UInt32)
        case cannotFetchAccount(index: UInt32)
    }
}
