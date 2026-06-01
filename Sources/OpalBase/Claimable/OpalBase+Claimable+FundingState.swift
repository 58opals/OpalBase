// OpalBase+Claimable+FundingState.swift

extension _OpalBase.Claimable {
    public enum FundingState: Sendable, Equatable {
        case missing
        case invalid
        case unspent
        case spent(spendPath: OpalBase.Claimable.SpendPath)
    }
}
