// ClaimableRecoveryMaterialValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable recovery material", .tags(.unit))
struct ClaimableRecoveryMaterialValidator {
    @Test("builds claim recovery material")
    func buildsClaimRecoveryMaterial() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .mainnet)
        let material = try envelope.makeClaimRecoveryMaterial()

        try assertRecoveryMaterial(
            material,
            envelope: envelope,
            spendPath: .claim,
            privateKey: envelope.claimPrivateKey,
            invalidPrivateKeyError: .invalidClaimPrivateKey
        )
        #expect(material.privateKeyWalletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
    }

    @Test("builds refund recovery material")
    func buildsRefundRecoveryMaterial() throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(network: .mainnet)
        let material = try envelope.makeRefundRecoveryMaterial(
            refundPrivateKey: refundPrivateKey
        )

        try assertRecoveryMaterial(
            material,
            envelope: envelope,
            spendPath: .refund,
            privateKey: refundPrivateKey,
            invalidPrivateKeyError: .invalidRefundPrivateKey
        )
    }

    @Test("normalizes sliced refund private key data")
    func normalizesSlicedRefundPrivateKeyData() throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(network: .mainnet)
        let slicedRefundPrivateKey = makeSlicedData(from: refundPrivateKey)

        let material = try envelope.makeRefundRecoveryMaterial(
            refundPrivateKey: slicedRefundPrivateKey
        )

        #expect(slicedRefundPrivateKey.startIndex != 0)
        #expect(material.privateKeyData == refundPrivateKey)
        #expect(material.privateKeyData.startIndex == 0)
    }

    @Test("rejects invalid refund recovery key")
    func rejectsInvalidRefundRecoveryKey() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()

        #expect(throws: OpalBase.Claimable.Error.invalidRefundPrivateKey) {
            try envelope.makeRefundRecoveryMaterial(
                refundPrivateKey: ClaimableTestSupport.makeClaimablePrivateKey(lastByte: 0x03)
            )
        }
    }

    @Test("formats network-aware wallet import format strings")
    func formatsNetworkAwareWalletImportFormatStrings() throws {
        let (mainnetEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .mainnet)
        let (chipnetEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let (testnetEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .testnet)

        let mainnetMaterial = try mainnetEnvelope.makeClaimRecoveryMaterial()
        let chipnetMaterial = try chipnetEnvelope.makeClaimRecoveryMaterial()
        let testnetMaterial = try testnetEnvelope.makeClaimRecoveryMaterial()

        #expect(mainnetMaterial.privateKeyWalletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
        #expect(chipnetMaterial.privateKeyWalletImportFormat == "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA")
        #expect(testnetMaterial.privateKeyWalletImportFormat == "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA")
    }

    private func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    private func assertRecoveryMaterial(
        _ material: OpalBase.Claimable.RecoveryMaterial,
        envelope: OpalBase.Claimable.Envelope,
        spendPath: OpalBase.Claimable.SpendPath,
        privateKey: Data,
        invalidPrivateKeyError: OpalBase.Claimable.Error
    ) throws {
        let expectedCompressedPublicKey = try makeClaimableCompressedPublicKey(
            from: privateKey,
            invalidError: invalidPrivateKeyError
        )

        #expect(material.network == envelope.contract.network)
        #expect(material.spendPath == spendPath)
        #expect(material.privateKeyData == privateKey)
        #expect(material.privateKeyHexadecimal == privateKey.hexadecimalString)
        #expect(material.privateKeyWalletImportFormat == (try makeClaimableWalletImportFormat(
            privateKey: privateKey,
            network: envelope.contract.network
        )))
        #expect(material.compressedPublicKeyData == expectedCompressedPublicKey)
        #expect(material.redeemScriptData == envelope.contract.redeemScriptData)
        #expect(material.redeemScriptHexadecimal == envelope.contract.redeemScriptData.hexadecimalString)
        #expect(material.fundingLockingScriptData == envelope.contract.fundingLockingScriptData)
        #expect(material.fundingLockingScriptHexadecimal == envelope.contract.fundingLockingScriptData.hexadecimalString)
        #expect(material.fundingScriptHashData == envelope.contract.fundingScriptHashData)
        #expect(material.fundingScriptHashHexadecimal == envelope.contract.fundingScriptHashData.hexadecimalString)
        #expect(material.fundingTransactionHash == envelope.fundingTransactionHash)
        #expect(material.fundingTransactionIdentifier == envelope.fundingTransactionHash.reverseOrder.hexadecimalString)
        #expect(material.fundingOutputIndex == envelope.fundingOutputIndex)
        #expect(material.fundingValueSatoshis == envelope.fundingValue)
        #expect(material.expiryBlockHeight == envelope.contract.expiryBlockHeight)
        #expect(material.encodedEnvelopeData == envelope.encode())
        #expect(material.encodedEnvelopeHexadecimal == envelope.encode().hexadecimalString)
    }
}
