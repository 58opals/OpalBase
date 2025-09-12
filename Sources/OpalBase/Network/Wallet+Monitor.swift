// Wallet+Monitor.swift

import Foundation

extension Wallet {
    public enum Monitor {}
}

extension Wallet.Monitor {
    public enum Error: Swift.Error {
        case emptyAccounts
        case monitoringFailed(Swift.Error)
    }
}
