// Network+Wallet+Monitor.swift

import Foundation

extension Network.Wallet {
    public actor Monitor {
        let wallet: Wallet
        
        public init(wallet: Wallet) {
            self.wallet = wallet
        }
    }
}

extension Network.Wallet.Monitor {
    public enum Error: Swift.Error {
        case emptyAccounts
        case monitoringFailed(Swift.Error)
    }
}
