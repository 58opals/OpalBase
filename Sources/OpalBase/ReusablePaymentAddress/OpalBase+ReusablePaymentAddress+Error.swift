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
        case invalidKeyOrigin
        case invalidHeightRange
        case invalidWindowSize
        case candidateReferenceConflict
        case candidateOutsideRequestedWindow
        case transactionHashMismatch
        case invalidPersistentState
        case persistentStateBindingMismatch
        case stateRevisionConflict
        case restorationOperationInProgress
        case matchedOutputNotFound
        case unspentOutputNotFound
        case unspentOutputPayloadMismatch
        case noQualifyingSenderInput
        case senderNetworkMismatch
        case invalidPrefixGrindingAttemptLimit
        case prefixGrindingExhausted(attempts: Int)
        case invalidPrefixGrindingCandidate
        case cashTokenPreservationRequired
    }
}
