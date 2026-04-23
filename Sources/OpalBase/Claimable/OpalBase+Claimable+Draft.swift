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
            let claimPrivateKey = try OpalCrypto.Secp256k1.generatePrivateKey()
            let claimPublicKeyHash = try makeClaimablePublicKeyHash(
                from: claimPrivateKey,
                invalidError: .invalidClaimPrivateKey
            )
            let refundPublicKeyHash = try makeClaimablePublicKeyHash(
                from: refundPrivateKey,
                invalidError: .invalidRefundPrivateKey
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
