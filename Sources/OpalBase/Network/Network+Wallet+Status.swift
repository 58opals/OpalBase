// Network+Wallet+Status.swift

extension Network.Wallet {
    public enum Status: Sendable {
        case offline
        case connecting
        case online
    }
}
