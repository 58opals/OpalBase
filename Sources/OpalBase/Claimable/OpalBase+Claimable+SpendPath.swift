// OpalBase+Claimable+SpendPath.swift

import Foundation

extension _OpalBase.Claimable {
    public enum SpendPath: Sendable, Equatable {
        case claim
        case refund
        case unknown
    }
}
