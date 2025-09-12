// Wallet+Network.swift

extension Wallet {
    public enum Network {}
}

extension Wallet.Network {
    public enum Error: Swift.Error {
        case noHealthyServer
        case connectionFailed(Swift.Error)
        case pingFailed(Swift.Error)
    }
}

extension Wallet.Network.Error: Equatable {
    public static func == (lhs: Wallet.Network.Error, rhs: Wallet.Network.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
