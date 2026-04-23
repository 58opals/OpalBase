// OpalBase+Claimable+Envelope.swift

import Foundation

extension _OpalBase.Claimable {
    public struct Envelope {
        public let contract: OpalBase.Claimable.Contract
        public let claimPrivateKey: Data
        public let fundingTransactionHash: OpalBase.Transaction.Hash
        public let fundingOutputIndex: UInt32
        public let fundingValue: UInt64

        public init(
            contract: OpalBase.Claimable.Contract,
            claimPrivateKey: Data,
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32,
            fundingValue: UInt64
        ) throws {
            let claimPublicKeyHash = try makeClaimablePublicKeyHash(
                from: claimPrivateKey,
                invalidError: .invalidClaimPrivateKey
            )
            guard claimPublicKeyHash == contract.claimPublicKeyHash else {
                throw OpalBase.Claimable.Error.invalidClaimPrivateKey
            }
            guard fundingTransactionHash.naturalOrder.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw OpalBase.Claimable.Error.invalidFundingReference
            }
            guard fundingValue > 0 else {
                throw OpalBase.Claimable.Error.invalidFundingOutput
            }

            self.contract = contract
            self.claimPrivateKey = claimPrivateKey
            self.fundingTransactionHash = fundingTransactionHash
            self.fundingOutputIndex = fundingOutputIndex
            self.fundingValue = fundingValue
        }

        public func makeLocalStatus(currentBlockHeight: UInt32) -> OpalBase.Claimable.LocalStatus {
            OpalBase.Claimable.LocalStatus(
                currentBlockHeight: currentBlockHeight,
                expiryBlockHeight: contract.expiryBlockHeight
            )
        }
    }
}

extension _OpalBase.Claimable.Envelope: Sendable {}
extension _OpalBase.Claimable.Envelope: Hashable {}
