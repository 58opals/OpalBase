// Network+Wallet.swift

import Foundation

extension Network {
    public enum Wallet {}
}

extension Network.Wallet {
    public enum Error: Swift.Error {
        case noHealthyServer
        case connectionFailed(Swift.Error)
        case pingFailed(Swift.Error)
        case healthRepositoryFailure(Storage.Repository.ServerHealth.Error)
    }
}

extension Network.Wallet.Error: Equatable {
    public static func == (lhs: Network.Wallet.Error, rhs: Network.Wallet.Error) -> Bool {
        switch (lhs, rhs) {
        case (.noHealthyServer, .noHealthyServer),
            (.connectionFailed, .connectionFailed),
            (.pingFailed, .pingFailed),
            (.healthRepositoryFailure, .healthRepositoryFailure):
            return true
        default:
            return false
        }
    }
}
