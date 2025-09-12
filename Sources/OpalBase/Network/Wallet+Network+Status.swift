// Wallet+Network+Status.swift

extension Wallet.Network {
    public enum Status: Sendable {
        case offline
        case connecting
        case online
    }
}
