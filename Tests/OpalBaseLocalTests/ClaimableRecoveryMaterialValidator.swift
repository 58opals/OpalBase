// ClaimableRecoveryMaterialValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable recovery material", .tags(.unit))
struct ClaimableRecoveryMaterialValidator {
    @Test("builds claim recovery material")
    func buildsClaimRecoveryMaterial() throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .mainnet)
        let material = try envelope.makeClaimRecoveryMaterial()
        let expectedCompressedPublicKey = try makeClaimableCompressedPublicKey(
            from: envelope.claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )

        #expect(material.network == .mainnet)
        #expect(material.spendPath == .claim)
        #expect(material.privateKeyData == envelope.claimPrivateKey)
        #expect(material.privateKeyHexadecimal == envelope.claimPrivateKey.hexadecimalString)
        #expect(material.privateKeyWalletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
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

    @Test("builds refund recovery material")
    func buildsRefundRecoveryMaterial() throws {
        let (envelope, refundPrivateKey) = try makeClaimableEnvelope(network: .mainnet)
        let material = try envelope.makeRefundRecoveryMaterial(
            refundPrivateKey: refundPrivateKey
        )
        let expectedCompressedPublicKey = try makeClaimableCompressedPublicKey(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )

        #expect(material.spendPath == .refund)
        #expect(material.privateKeyData == refundPrivateKey)
        #expect(material.compressedPublicKeyData == expectedCompressedPublicKey)
    }

    @Test("rejects invalid refund recovery key")
    func rejectsInvalidRefundRecoveryKey() throws {
        let (envelope, _) = try makeClaimableEnvelope()

        #expect(throws: OpalBase.Claimable.Error.invalidRefundPrivateKey) {
            try envelope.makeRefundRecoveryMaterial(
                refundPrivateKey: makeClaimablePrivateKey(lastByte: 0x03)
            )
        }
    }

    @Test("formats network-aware wallet import format strings")
    func formatsNetworkAwareWalletImportFormatStrings() throws {
        let (mainnetEnvelope, _) = try makeClaimableEnvelope(network: .mainnet)
        let (chipnetEnvelope, _) = try makeClaimableEnvelope(network: .chipnet)
        let (testnetEnvelope, _) = try makeClaimableEnvelope(network: .testnet)

        let mainnetMaterial = try mainnetEnvelope.makeClaimRecoveryMaterial()
        let chipnetMaterial = try chipnetEnvelope.makeClaimRecoveryMaterial()
        let testnetMaterial = try testnetEnvelope.makeClaimRecoveryMaterial()

        #expect(mainnetMaterial.privateKeyWalletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
        #expect(chipnetMaterial.privateKeyWalletImportFormat == "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA")
        #expect(testnetMaterial.privateKeyWalletImportFormat == "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA")
    }
}
