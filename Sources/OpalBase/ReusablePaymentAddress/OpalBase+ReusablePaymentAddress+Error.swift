// OpalBase+ReusablePaymentAddress+Error.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public enum Error: Swift.Error, Sendable, Equatable {
        case invalidEncoding
        case invalidChecksum
        case invalidPayloadLength(Int)
        case unsupportedScheme
        case unsupportedVersion(UInt8)
        case networkMismatch
        case unsupportedPrefixLength(UInt8)
        case unsupportedExpiration
        case invalidPublicKey
        case legacyProfileIsReadOnly
        case unsupportedProfile(Profile)
        case scanSigningKeyMismatch
        case spendSigningKeyMismatch
        case invalidSerializedTransaction
        case invalidOutpointTransactionHash
        case invalidDerivationDigest
        case childKeyDerivationFailed
    }
}
