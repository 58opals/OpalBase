// OpalBase+Claimable+SpendPath.swift

extension _OpalBase.Claimable {
    public enum SpendPath: Sendable, Equatable {
        case claim
        case refund
        case unknown
    }
}
