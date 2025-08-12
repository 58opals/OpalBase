// Wallet+Monitor+Error.swift

import Foundation

extension Wallet.Monitor {
    public enum Error: Swift.Error {
        case emptyAccounts
        case monitoringFailed(Swift.Error)
    }
}
