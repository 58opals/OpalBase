// OpalBase+Claimable+Contract.swift

import Foundation

extension _OpalBase.Claimable {
    public struct Contract {
        public let network: OpalBase.Network.Environment
        public let claimPublicKeyHash: Data
        public let refundPublicKeyHash: Data
        public let expiryBlockHeight: UInt32

        public init(
            network: OpalBase.Network.Environment,
            claimPublicKeyHash: Data,
            refundPublicKeyHash: Data,
            expiryBlockHeight: UInt32
        ) throws {
            guard claimPublicKeyHash.count == 20 else {
                throw OpalBase.Claimable.Error.invalidClaimPublicKeyHash
            }
            guard refundPublicKeyHash.count == 20 else {
                throw OpalBase.Claimable.Error.invalidRefundPublicKeyHash
            }

            self.network = network
            self.claimPublicKeyHash = claimPublicKeyHash
            self.refundPublicKeyHash = refundPublicKeyHash
            self.expiryBlockHeight = expiryBlockHeight
        }
    }
}

extension _OpalBase.Claimable.Contract: Sendable {}
extension _OpalBase.Claimable.Contract: Hashable {}
