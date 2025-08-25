// Wallet+Network+Error.swift

extension Wallet.Network {
    public enum Error: Swift.Error {
        case noHealthyServer
        case connectionFailed(Swift.Error)
    }
}
