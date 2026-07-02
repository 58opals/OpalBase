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
            let claimPublicKeyHash = try ClaimablePrimitiveOperation.makePublicKeyHash(
                from: claimPrivateKey,
                invalidError: .invalidClaimPrivateKey
            )
            guard claimPublicKeyHash == contract.claimPublicKeyHash else {
                throw OpalBase.Claimable.Error.invalidClaimPrivateKey
            }
            guard fundingTransactionHash.naturalOrder.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw OpalBase.Claimable.Error.invalidFundingReference
            }
            guard (1...OpalBase.Satoshi.maximumSatoshi).contains(fundingValue) else {
                throw OpalBase.Claimable.Error.invalidFundingOutput
            }

            self.contract = contract
            self.claimPrivateKey = Data(claimPrivateKey)
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
extension _OpalBase.Claimable.Envelope: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "OpalBase.Claimable.Envelope(network: \(contract.network), claimPrivateKey: \(OpalBase.Claimable.redactedSecretMarker), fundingOutputIndex: \(fundingOutputIndex))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "network": contract.network,
                "claimPrivateKey": OpalBase.Claimable.redactedSecretMarker,
                "fundingTransactionHash": fundingTransactionHash,
                "fundingOutputIndex": fundingOutputIndex,
                "fundingValue": fundingValue,
            ],
            displayStyle: .struct
        )
    }
}
