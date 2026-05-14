// OpalBase+Claimable+Envelope~TransactionBuilding.swift

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

        let compressedPublicKey = try makeClaimableCompressedPublicKey(
            from: claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        return try buildClaimableSpendTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: feePerByte,
            signingPrivateKey: claimPrivateKey,
            compressedPublicKey: compressedPublicKey,
            isRefund: false
        )
    }

    public func buildRefundTransaction(
        refundPrivateKey: Data,
        destinationLockingScript: Data,
        feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
        currentBlockHeight: UInt32
    ) throws -> OpalBase.Transaction {
        guard makeLocalStatus(currentBlockHeight: currentBlockHeight).allowsRefund else {
            throw OpalBase.Claimable.Error.refundRequiresExpiry
        }

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
        return try buildClaimableSpendTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: feePerByte,
            signingPrivateKey: refundPrivateKey,
            compressedPublicKey: compressedPublicKey,
            isRefund: true
        )
    }
}

private extension _OpalBase.Claimable.Envelope {
    var fundingOutput: OpalBase.Transaction.Output {
        OpalBase.Transaction.Output(
            value: fundingValue,
            lockingScript: contract.fundingLockingScriptData
        )
    }

    var signingOutput: OpalBase.Transaction.Output {
        OpalBase.Transaction.Output(
            value: fundingValue,
            lockingScript: contract.redeemScriptData
        )
    }

    func buildClaimableSpendTransaction(
        destinationLockingScript: Data,
        feePerByte: UInt64,
        signingPrivateKey: Data,
        compressedPublicKey: Data,
        isRefund: Bool
    ) throws -> OpalBase.Transaction {
        guard fundingValue > 0 else {
            throw OpalBase.Claimable.Error.invalidFundingOutput
        }

        let sequence: UInt32 = isRefund ? 0xFFFFFFFE : 0xFFFFFFFF
        let lockTime: UInt32 = isRefund ? contract.expiryBlockHeight : 0
        let placeholderUnlockingScript = makeClaimablePlaceholderUnlockingScript(
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

        let hashType = OpalBase.Transaction.HashType.makeAll(anyoneCanPay: false)
        let preimage = try unsignedTransaction.generatePreimage(
            for: 0,
            hashType: hashType,
            outputBeingSpent: signingOutput
        )
        let signature = try OpalCrypto.Signature.Schnorr.sign(
            digest: OpalCrypto.Signature.Digest(rawRepresentation: OpalCryptoAdapter.hash256(preimage)),
            privateKey: OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: signingPrivateKey)
        ).rawRepresentation
        let signatureWithHashType = signature + Data([UInt8(hashType.value)])
        let unlockingScript = makeClaimableUnlockingScript(
            signatureWithHashType: signatureWithHashType,
            compressedPublicKey: compressedPublicKey,
            redeemScriptData: contract.redeemScriptData,
            isRefund: isRefund
        )

        return try unsignedTransaction.injectUnlockingScript(unlockingScript, inputIndex: 0)
    }
}

private func makeClaimablePlaceholderUnlockingScript(
    redeemScriptData: Data,
    isRefund: Bool
) -> Data {
    makeClaimableUnlockingScript(
        signatureWithHashType: Data(count: 65),
        compressedPublicKey: Data(count: 33),
        redeemScriptData: redeemScriptData,
        isRefund: isRefund
    )
}

private func makeClaimableUnlockingScript(
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
