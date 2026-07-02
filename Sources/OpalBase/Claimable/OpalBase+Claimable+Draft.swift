// OpalBase+Claimable+Draft.swift

import Foundation
import OpalCrypto

extension _OpalBase.Claimable {
    public struct Draft {
        public let contract: OpalBase.Claimable.Contract
        public let claimPrivateKey: Data

        public init(
            network: OpalBase.Network.Environment,
            refundPrivateKey: Data,
            expiryBlockHeight: UInt32
        ) throws {
            try self.init(
                network: network,
                refundSigningKey: ClaimablePrimitiveOperation.makeSigningKey(
                    from: refundPrivateKey,
                    invalidError: .invalidRefundPrivateKey
                ),
                expiryBlockHeight: expiryBlockHeight
            )
        }

        public init(
            network: OpalBase.Network.Environment,
            refundSigningKey: OpalBase.Key.SigningKey,
            expiryBlockHeight: UInt32
        ) throws {
            try OpalBase.Claimable.Contract.validateExpiryBlockHeight(expiryBlockHeight)
            let claimPrivateKey = try OpalCrypto.Secp256k1.PrivateKey.generate().rawRepresentation
            let claimSigningKey = try ClaimablePrimitiveOperation.makeSigningKey(
                from: claimPrivateKey,
                invalidError: .invalidClaimPrivateKey
            )
            let claimPublicKeyHash = ClaimablePrimitiveOperation.makePublicKeyHash(
                from: claimSigningKey
            )
            let refundPublicKeyHash = ClaimablePrimitiveOperation.makePublicKeyHash(
                from: refundSigningKey
            )

            self.contract = try .init(
                network: network,
                claimPublicKeyHash: claimPublicKeyHash,
                refundPublicKeyHash: refundPublicKeyHash,
                expiryBlockHeight: expiryBlockHeight
            )
            self.claimPrivateKey = claimPrivateKey
        }

        public func makeFundingOutput(value: UInt64) -> OpalBase.Transaction.Output {
            OpalBase.Transaction.Output(
                value: value,
                lockingScript: contract.fundingLockingScriptData
            )
        }
    }
}

extension _OpalBase.Claimable.Draft: Sendable {}
extension _OpalBase.Claimable.Draft: Hashable {}
extension _OpalBase.Claimable.Draft: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "OpalBase.Claimable.Draft(network: \(contract.network), claimPrivateKey: \(OpalBase.Claimable.redactedSecretMarker))"
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
            ],
            displayStyle: .struct
        )
    }
}
