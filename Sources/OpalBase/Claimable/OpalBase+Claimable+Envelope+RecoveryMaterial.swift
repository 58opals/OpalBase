// OpalBase+Claimable+Envelope+RecoveryMaterial.swift

import Foundation

extension _OpalBase.Claimable.Envelope {
    public func makeClaimRecoveryMaterial() throws -> OpalBase.Claimable.RecoveryMaterial {
        let compressedPublicKey = try makeClaimableCompressedPublicKey(
            from: claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        return try OpalBase.Claimable.RecoveryMaterial(
            envelope: self,
            spendPath: .claim,
            privateKeyData: claimPrivateKey,
            compressedPublicKeyData: compressedPublicKey
        )
    }

    public func makeRefundRecoveryMaterial(
        refundPrivateKey: Data
    ) throws -> OpalBase.Claimable.RecoveryMaterial {
        let refundPublicKeyHash = try makeClaimablePublicKeyHash(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )
        guard refundPublicKeyHash == contract.refundPublicKeyHash else {
            throw OpalBase.Claimable.Error.invalidRefundPrivateKey
        }

        let compressedPublicKey = try makeClaimableCompressedPublicKey(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )
        return try OpalBase.Claimable.RecoveryMaterial(
            envelope: self,
            spendPath: .refund,
            privateKeyData: refundPrivateKey,
            compressedPublicKeyData: compressedPublicKey
        )
    }
}
