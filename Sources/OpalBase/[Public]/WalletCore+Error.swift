// WalletCore+Error.swift

import Foundation

extension WalletCore {
    public enum Error: Swift.Error, Sendable {
        case syncFailed(Swift.Error)
        case storage(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
    }
}
