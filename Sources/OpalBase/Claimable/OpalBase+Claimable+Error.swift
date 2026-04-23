// OpalBase+Claimable+Error.swift

import Foundation

extension _OpalBase.Claimable {
    public enum Error: Swift.Error, Equatable {
        case unsupportedVersion(UInt8)
        case invalidNetworkTag(UInt8)
        case invalidEnvelopeLength(expected: Int, actual: Int)
        case networkMismatch(expected: OpalBase.Network.Environment, actual: OpalBase.Network.Environment)
        case invalidClaimPrivateKey
        case invalidRefundPrivateKey
        case invalidClaimPublicKeyHash
        case invalidRefundPublicKeyHash
        case invalidFundingReference
        case invalidFundingOutput
        case claimRequiresPreExpiry
        case refundRequiresExpiry
        case insufficientFundingValue(required: UInt64)
        case dustOutput(requiredMinimum: UInt64)
    }
}
