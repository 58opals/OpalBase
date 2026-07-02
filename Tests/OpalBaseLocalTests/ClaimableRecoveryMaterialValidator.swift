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

    @Test("redacts recovery material text and reflection")
    func redactsRecoveryMaterialTextAndReflection() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .mainnet)
        let material = try envelope.makeClaimRecoveryMaterial()

        ClaimableTestSupport.expectRedactedSecretDebugSurfaces(
            of: material,
            secretTexts: [
                material.privateKeyHexadecimal,
                material.privateKeyWalletImportFormat,
                material.encodedEnvelopeHexadecimal,
            ],
            redactedLabel: "privateKey"
        )
        let reflectedLabels = Mirror(reflecting: material).children.compactMap(\.label)
        #expect(reflectedLabels.contains("privateKeyData") == false)
        #expect(reflectedLabels.contains("privateKeyWalletImportFormat") == false)
        #expect(reflectedLabels.contains("encodedEnvelopeData") == false)
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

    @Test(
        "formats network-aware wallet import format strings",
        arguments: WalletImportFormatCase.allCases
    )
    func formatsNetworkAwareWalletImportFormatStrings(_ formatCase: WalletImportFormatCase) throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: formatCase.network)
        let material = try envelope.makeClaimRecoveryMaterial()

        #expect(material.privateKeyWalletImportFormat == formatCase.expectedWalletImportFormat)
    }

    @Test("wallet import format preserves refund invalid-key errors")
    func walletImportFormatPreservesRefundInvalidKeyErrors() throws {
        #expect(throws: OpalBase.Claimable.Error.invalidRefundPrivateKey) {
            _ = try ClaimablePrimitiveOperation.makeWalletImportFormat(
                privateKey: Data(repeating: 0x01, count: 31),
                network: .mainnet,
                invalidError: .invalidRefundPrivateKey
            )
        }
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
        let expectedCompressedPublicKey = try ClaimablePrimitiveOperation.makeCompressedPublicKey(
            from: privateKey,
            invalidError: invalidPrivateKeyError
        )

        #expect(material.network == envelope.contract.network)
        #expect(material.spendPath == spendPath)
        #expect(material.privateKeyData == privateKey)
        #expect(material.privateKeyHexadecimal == privateKey.hexadecimalString)
        #expect(material.privateKeyWalletImportFormat == (try ClaimablePrimitiveOperation.makeWalletImportFormat(
            privateKey: privateKey,
            network: envelope.contract.network,
            invalidError: invalidPrivateKeyError
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

    enum WalletImportFormatCase: CaseIterable, CustomStringConvertible, Sendable {
        case mainnet
        case chipnet
        case testnet

        var description: String {
            switch self {
            case .mainnet:
                "mainnet"
            case .chipnet:
                "chipnet"
            case .testnet:
                "testnet"
            }
        }

        var network: OpalBase.Network.Environment {
            switch self {
            case .mainnet:
                .mainnet
            case .chipnet:
                .chipnet
            case .testnet:
                .testnet
            }
        }

        var expectedWalletImportFormat: String {
            switch self {
            case .mainnet:
                "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
            case .chipnet, .testnet:
                "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA"
            }
        }
    }
}
