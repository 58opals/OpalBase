// WalletCore.swift

import Foundation

public actor WalletCore {
    
}

extension WalletCore {
    public enum Error: Swift.Error, Sendable {
        case storage(Swift.Error)
        case syncFailed(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
    }
}
