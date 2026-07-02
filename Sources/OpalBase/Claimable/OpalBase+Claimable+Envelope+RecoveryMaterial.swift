// OpalBase+Claimable+Envelope+RecoveryMaterial.swift

import Foundation

extension _OpalBase.Claimable.Envelope {
    public func makeClaimRecoveryMaterial() throws -> OpalBase.Claimable.RecoveryMaterial {
        let compressedPublicKey = try ClaimablePrimitiveOperation.makeCompressedPublicKey(
            from: claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        return try OpalBase.Claimable.RecoveryMaterial(
            envelope: self,
            spendPath: .claim,
            privateKeyData: claimPrivateKey,
            compressedPublicKeyData: compressedPublicKey,
            invalidPrivateKeyError: .invalidClaimPrivateKey
        )
    }

    public func makeRefundRecoveryMaterial(
        refundPrivateKey: Data
    ) throws -> OpalBase.Claimable.RecoveryMaterial {
        let refundSigningKey = try ClaimablePrimitiveOperation.makeSigningKey(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )
        let compressedPublicKey = try makeValidatedRefundCompressedPublicKey(
            from: refundSigningKey
        )
        return try OpalBase.Claimable.RecoveryMaterial(
            envelope: self,
            spendPath: .refund,
            privateKeyData: refundPrivateKey,
            compressedPublicKeyData: compressedPublicKey,
            invalidPrivateKeyError: .invalidRefundPrivateKey
        )
    }
}

extension _OpalBase.Claimable.Envelope {
    func makeValidatedRefundCompressedPublicKey(
        from refundSigningKey: OpalBase.Key.SigningKey
    ) throws -> Data {
        let refundPublicKeyHash = ClaimablePrimitiveOperation.makePublicKeyHash(
            from: refundSigningKey
        )
        guard refundPublicKeyHash == contract.refundPublicKeyHash else {
            throw OpalBase.Claimable.Error.invalidRefundPrivateKey
        }

        return ClaimablePrimitiveOperation.makeCompressedPublicKey(
            from: refundSigningKey
        )
    }
}
