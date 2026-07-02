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
            try Self.validateExpiryBlockHeight(expiryBlockHeight)

            self.network = network
            self.claimPublicKeyHash = Data(claimPublicKeyHash)
            self.refundPublicKeyHash = Data(refundPublicKeyHash)
            self.expiryBlockHeight = expiryBlockHeight
        }

        static func validateExpiryBlockHeight(_ expiryBlockHeight: UInt32) throws {
            guard expiryBlockHeight < 500_000_000 else {
                throw OpalBase.Claimable.Error.invalidExpiryBlockHeight
            }
        }
    }
}

extension _OpalBase.Claimable.Contract: Sendable {}
extension _OpalBase.Claimable.Contract: Hashable {}
