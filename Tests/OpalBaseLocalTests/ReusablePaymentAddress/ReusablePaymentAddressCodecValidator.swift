// ReusablePaymentAddressCodecValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Reusable payment address codec", .tags(.unit))
struct ReusablePaymentAddressCodecValidator {
    @Test("Cash Code v1 encodes exact independent mainnet and testnet vectors")
    func encodeCashCodeV1Vectors() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()

        #expect(
            try codec.encode(
                ReusablePaymentAddressFixtureData.makeAddress(network: .mainnet)
            ) == ReusablePaymentAddressFixtureData.cashCodeMainnet
        )
        #expect(
            try codec.encode(
                ReusablePaymentAddressFixtureData.makeAddress(network: .testnet)
            ) == ReusablePaymentAddressFixtureData.cashCodeTestnet
        )
    }

    @Test("Cash Code v1 parses exact fields and canonicalizes uniform uppercase")
    func parseCashCodeV1Fields() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()
        let address = try codec.parse(
            ReusablePaymentAddressFixtureData.cashCodeMainnet.uppercased(),
            network: .mainnet
        )
        let expectedScanPublicKey = try ReusablePaymentAddressFixtureData.makeScanPublicKey()
        let expectedSpendPublicKey = try ReusablePaymentAddressFixtureData.makeSpendPublicKey()

        #expect(address.profile == .cashCodeV1)
        #expect(address.network == .mainnet)
        #expect(address.prefixLength == .sixteenBits)
        #expect(address.expiration == .never)
        #expect(address.scanPublicKey == expectedScanPublicKey)
        #expect(address.spendPublicKey == expectedSpendPublicKey)
        #expect(try codec.encode(address) == ReusablePaymentAddressFixtureData.cashCodeMainnet)
    }

    @Test("legacy Electron Cash paycodes parse as read-only recovery profiles")
    func parseLegacyElectronCashProfiles() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()
        let mainnet = try codec.parse(
            ReusablePaymentAddressFixtureData.legacyPaycodeMainnet,
            network: .mainnet
        )
        let testnet = try codec.parse(
            ReusablePaymentAddressFixtureData.legacyPaycodeTestnet,
            network: .testnet
        )

        #expect(mainnet.profile == .legacyElectronCash)
        #expect(mainnet.network == .mainnet)
        #expect(mainnet.prefixLength == .sixteenBits)
        #expect(mainnet.expiration == .never)
        #expect(testnet.profile == .legacyElectronCash)
        #expect(testnet.network == .testnet)
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.legacyProfileIsReadOnly) {
            _ = try codec.encode(mainnet)
        }
    }

    @Test("legacy parser accepts exactly Electron Cash prefix bit lengths")
    func parseLegacyElectronCashPrefixBitLengths() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()

        for expected in [
            OpalBase.ReusablePaymentAddress.PrefixLength.fourBits,
            .eightBits,
            .twelveBits,
            .sixteenBits,
        ] {
            var payload = ReusablePaymentAddressFixtureData
                .applicationPayload
            payload[1] = expected.rawValue
            let encoded = try ReusablePaymentAddressFixtureData
                .makeEncodedIdentifier(
                    scheme: "paycode",
                    payload: payload
                )

            #expect(
                try codec.parse(encoded, network: .mainnet)
                    .prefixLength == expected
            )
        }

        var unsupportedPayload = ReusablePaymentAddressFixtureData
            .applicationPayload
        unsupportedPayload[1] = 20
        let unsupported = try ReusablePaymentAddressFixtureData
            .makeEncodedIdentifier(
                scheme: "paycode",
                payload: unsupportedPayload
            )
        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .unsupportedPrefixLength(20)
        ) {
            _ = try codec.parse(unsupported, network: .mainnet)
        }
    }

    @Test("legacy parser preserves nonzero Unix expiration")
    func parseLegacyElectronCashUnixExpiration() throws {
        var payload = ReusablePaymentAddressFixtureData.applicationPayload
        payload.replaceSubrange(
            68..<72,
            with: [0x65, 0x53, 0xf1, 0x00]
        )
        let encoded = try ReusablePaymentAddressFixtureData
            .makeEncodedIdentifier(
                scheme: "paycode",
                payload: payload
            )

        let legacy = try OpalBase.ReusablePaymentAddress.Codec().parse(
            encoded,
            network: .mainnet
        )

        #expect(legacy.expiration == .unixTime(1_700_000_000))
    }

    @Test("testnet and chipnet share wire bytes but retain caller context")
    func retainTestNetworkContext() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()
        let chipnet = try ReusablePaymentAddressFixtureData.makeAddress(
            network: .chipnet
        )

        #expect(
            try codec.encode(chipnet)
                == ReusablePaymentAddressFixtureData.cashCodeTestnet
        )
        #expect(
            try codec.parse(
                ReusablePaymentAddressFixtureData.cashCodeTestnet,
                network: .chipnet
            ).network == .chipnet
        )
        #expect(
            try codec.parse(
                ReusablePaymentAddressFixtureData.cashCodeTestnet,
                network: .testnet
            ).network == .testnet
        )
    }

    @Test("codec rejects network and scheme reinterpretation")
    func rejectNetworkAndSchemeReinterpretation() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()

        #expect(throws: OpalBase.ReusablePaymentAddress.Error.networkMismatch) {
            _ = try codec.parse(
                ReusablePaymentAddressFixtureData.cashCodeMainnet,
                network: .testnet
            )
        }
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.unsupportedScheme) {
            _ = try codec.parse(
                ReusablePaymentAddressFixtureData.cashCodeMainnet
                    .replacingOccurrences(of: "cashcode:", with: "rpa:"),
                network: .mainnet
            )
        }
    }

    @Test("codec rejects checksum, case, payload framing, and profile mutations")
    func rejectInvalidWireValues() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()
        let checksumMutation = String(
            ReusablePaymentAddressFixtureData.cashCodeMainnet.dropLast()
        ) + "q"
        let mixedCase = "Cashcode:"
            + ReusablePaymentAddressFixtureData.cashCodeMainnet.split(separator: ":")[1]

        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidChecksum) {
            _ = try codec.parse(checksumMutation, network: .mainnet)
        }
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidChecksum) {
            _ = try codec.parse(
                ReusablePaymentAddressFixtureData.cashCodeMainnet
                    .replacingOccurrences(
                        of: "cashcode:",
                        with: "paycode:"
                    ),
                network: .mainnet
            )
        }
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidEncoding) {
            _ = try codec.parse(mixedCase, network: .mainnet)
        }
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidPayloadLength(73)) {
            _ = try codec.parse(
                ReusablePaymentAddressFixtureData.incompatibleCashAddrFraming,
                network: .mainnet
            )
        }

        var unsupportedVersionPayload = ReusablePaymentAddressFixtureData.applicationPayload
        unsupportedVersionPayload[0] = 2
        let unsupportedVersion = try ReusablePaymentAddressFixtureData.makeEncodedIdentifier(
            scheme: "cashcode",
            payload: unsupportedVersionPayload
        )
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.unsupportedVersion(2)) {
            _ = try codec.parse(unsupportedVersion, network: .mainnet)
        }

        var unsupportedPrefixPayload = ReusablePaymentAddressFixtureData.applicationPayload
        unsupportedPrefixPayload[1] = 12
        let unsupportedPrefix = try ReusablePaymentAddressFixtureData.makeEncodedIdentifier(
            scheme: "cashcode",
            payload: unsupportedPrefixPayload
        )
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.unsupportedPrefixLength(12)) {
            _ = try codec.parse(unsupportedPrefix, network: .mainnet)
        }

        var expiringPayload = ReusablePaymentAddressFixtureData.applicationPayload
        expiringPayload[71] = 1
        let expiring = try ReusablePaymentAddressFixtureData.makeEncodedIdentifier(
            scheme: "cashcode",
            payload: expiringPayload
        )
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.unsupportedExpiration) {
            _ = try codec.parse(expiring, network: .mainnet)
        }

        var invalidPublicKeyPayload = ReusablePaymentAddressFixtureData.applicationPayload
        invalidPublicKeyPayload[2] = 4
        let invalidPublicKey = try ReusablePaymentAddressFixtureData.makeEncodedIdentifier(
            scheme: "cashcode",
            payload: invalidPublicKeyPayload
        )
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidPublicKey) {
            _ = try codec.parse(invalidPublicKey, network: .mainnet)
        }
    }
}
