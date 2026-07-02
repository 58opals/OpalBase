// OpalBase+Claimable+Envelope+TransactionBuilding.swift

import Foundation
import OpalCrypto

extension _OpalBase.Claimable.Envelope {
    public func buildClaimTransaction(
        destinationLockingScript: Data,
        feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
        currentBlockHeight: UInt32
    ) throws -> OpalBase.Transaction {
        guard makeLocalStatus(currentBlockHeight: currentBlockHeight).allowsClaim else {
            throw OpalBase.Claimable.Error.claimRequiresPreExpiry
        }

        let template = try makeClaimableSpendTemplate(
            destinationLockingScript: destinationLockingScript,
            feePerByte: feePerByte,
            isRefund: false
        )
        let claimSigningKey = try ClaimablePrimitiveOperation.makeSigningKey(
            from: claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        let compressedPublicKey = ClaimablePrimitiveOperation.makeCompressedPublicKey(
            from: claimSigningKey
        )
        return try signClaimableSpendTransaction(
            template,
            signingKey: claimSigningKey,
            compressedPublicKey: compressedPublicKey
        )
    }

    public func buildRefundTransaction(
        refundPrivateKey: Data,
        destinationLockingScript: Data,
        feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
        currentBlockHeight: UInt32
    ) throws -> OpalBase.Transaction {
        let template = try makeRefundSpendTemplate(
            destinationLockingScript: destinationLockingScript,
            feePerByte: feePerByte,
            currentBlockHeight: currentBlockHeight
        )
        return try buildRefundTransaction(
            refundSigningKey: ClaimablePrimitiveOperation.makeSigningKey(
                from: refundPrivateKey,
                invalidError: .invalidRefundPrivateKey
            ),
            template: template
        )
    }

    public func buildRefundTransaction(
        refundSigningKey: OpalBase.Key.SigningKey,
        destinationLockingScript: Data,
        feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
        currentBlockHeight: UInt32
    ) throws -> OpalBase.Transaction {
        let template = try makeRefundSpendTemplate(
            destinationLockingScript: destinationLockingScript,
            feePerByte: feePerByte,
            currentBlockHeight: currentBlockHeight
        )
        return try buildRefundTransaction(
            refundSigningKey: refundSigningKey,
            template: template
        )
    }
}

private extension _OpalBase.Claimable.Envelope {
    struct ClaimableSpendTemplate {
        let unsignedTransaction: OpalBase.Transaction
        let isRefund: Bool
    }

    var signingOutput: OpalBase.Transaction.Output {
        OpalBase.Transaction.Output(
            value: fundingValue,
            lockingScript: contract.redeemScriptData
        )
    }

    func buildRefundTransaction(
        refundSigningKey: OpalBase.Key.SigningKey,
        template: ClaimableSpendTemplate
    ) throws -> OpalBase.Transaction {
        let compressedPublicKey = try makeValidatedRefundCompressedPublicKey(
            from: refundSigningKey
        )

        return try signClaimableSpendTransaction(
            template,
            signingKey: refundSigningKey,
            compressedPublicKey: compressedPublicKey
        )
    }

    func makeRefundSpendTemplate(
        destinationLockingScript: Data,
        feePerByte: UInt64,
        currentBlockHeight: UInt32
    ) throws -> ClaimableSpendTemplate {
        guard makeLocalStatus(currentBlockHeight: currentBlockHeight).allowsRefund else {
            throw OpalBase.Claimable.Error.refundRequiresExpiry
        }

        return try makeClaimableSpendTemplate(
            destinationLockingScript: destinationLockingScript,
            feePerByte: feePerByte,
            isRefund: true
        )
    }

    func makeClaimableSpendTemplate(
        destinationLockingScript: Data,
        feePerByte: UInt64,
        isRefund: Bool
    ) throws -> ClaimableSpendTemplate {
        guard fundingValue > 0 else {
            throw OpalBase.Claimable.Error.invalidFundingOutput
        }

        let sequence: UInt32 = isRefund ? 0xFFFFFFFE : 0xFFFFFFFF
        let lockTime: UInt32 = isRefund ? contract.expiryBlockHeight : 0
        let placeholderUnlockingScript = Self.makePlaceholderUnlockingScript(
            redeemScriptData: contract.redeemScriptData,
            isRefund: isRefund
        )
        let placeholderInput = OpalBase.Transaction.Input(
            previousTransactionHash: fundingTransactionHash,
            previousTransactionOutputIndex: fundingOutputIndex,
            unlockingScript: placeholderUnlockingScript,
            sequence: sequence
        )
        let placeholderOutput = OpalBase.Transaction.Output(
            value: 0,
            lockingScript: destinationLockingScript
        )
        let placeholderTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [placeholderInput],
            outputs: [placeholderOutput],
            lockTime: lockTime
        )
        let fee = try placeholderTransaction.calculateFee(feePerByte: feePerByte)
        guard fundingValue > fee else {
            let requiredValue = fee == UInt64.max ? fee : fee + 1
            throw OpalBase.Claimable.Error.insufficientFundingValue(required: requiredValue)
        }

        let sweepValue = fundingValue - fee
        let destinationOutput = OpalBase.Transaction.Output(
            value: sweepValue,
            lockingScript: destinationLockingScript
        )
        guard !destinationOutput.isOpReturnScript else {
            throw OpalBase.Claimable.Error.invalidDestinationOutput
        }
        let dustThreshold = try destinationOutput.calculateDustThreshold(
            feeRate: OpalBase.Transaction.minimumRelayFeeRate
        )
        guard sweepValue >= dustThreshold else {
            throw OpalBase.Claimable.Error.dustOutput(requiredMinimum: dustThreshold)
        }

        let unsignedInput = OpalBase.Transaction.Input(
            previousTransactionHash: fundingTransactionHash,
            previousTransactionOutputIndex: fundingOutputIndex,
            unlockingScript: Data(),
            sequence: sequence
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [unsignedInput],
            outputs: [destinationOutput],
            lockTime: lockTime
        )

        return ClaimableSpendTemplate(
            unsignedTransaction: unsignedTransaction,
            isRefund: isRefund
        )
    }

    func signClaimableSpendTransaction(
        _ template: ClaimableSpendTemplate,
        signingKey: OpalBase.Key.SigningKey,
        compressedPublicKey: Data
    ) throws -> OpalBase.Transaction {
        let hashType = OpalBase.Transaction.HashType.makeAll(anyoneCanPay: false)
        let preimage = try template.unsignedTransaction.generatePreimage(
            for: 0,
            hashType: hashType,
            outputBeingSpent: signingOutput
        )
        let signatureDigest = try OpalCrypto.Signature.Digest(
            rawRepresentation: OpalCryptoAdapter.hash256(preimage)
        )
        let signature = try signingKey.signSchnorr(digest: signatureDigest).rawRepresentation
        let signatureWithHashType = signature + Data([UInt8(hashType.value)])
        let unlockingScript = Self.makeUnlockingScript(
            signatureWithHashType: signatureWithHashType,
            compressedPublicKey: compressedPublicKey,
            redeemScriptData: contract.redeemScriptData,
            isRefund: template.isRefund
        )

        return try template.unsignedTransaction.injectUnlockingScript(unlockingScript, inputIndex: 0)
    }

    private static func makePlaceholderUnlockingScript(
        redeemScriptData: Data,
        isRefund: Bool
    ) -> Data {
        makeUnlockingScript(
            signatureWithHashType: Data(count: 65),
            compressedPublicKey: Data(count: 33),
            redeemScriptData: redeemScriptData,
            isRefund: isRefund
        )
    }

    private static func makeUnlockingScript(
        signatureWithHashType: Data,
        compressedPublicKey: Data,
        redeemScriptData: Data,
        isRefund: Bool
    ) -> Data {
        Data.push(signatureWithHashType)
            + Data.push(compressedPublicKey)
            + (isRefund ? ScriptOperationCode._0.data : ScriptOperationCode._1.data)
            + Data.push(redeemScriptData)
    }
}
