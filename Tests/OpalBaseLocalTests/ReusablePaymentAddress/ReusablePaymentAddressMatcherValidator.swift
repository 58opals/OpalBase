// ReusablePaymentAddressMatcherValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Cash Code transaction matching", .tags(.unit))
struct ReusablePaymentAddressMatcherValidator {
    @Test("receiver matches the independent CashToken output vector")
    func receiverMatchesIndependentCashTokenOutputVector() throws {
        let rawTransaction = try Data(
            hexadecimalString:
                ReusablePaymentAddressFixtureData.positiveTransactionHex
        )
        let decoded = try OpalBase.Transaction.decode(from: rawTransaction)

        let matches = try makeMatcher().matches(
            in: rawTransaction,
            for: ReusablePaymentAddressFixtureData.makeAddress(),
            scanSigningKey:
                ReusablePaymentAddressFixtureData.makeScanSigningKey(),
            spendSigningKey:
                ReusablePaymentAddressFixtureData.makeSpendSigningKey()
        )

        let match = try #require(matches.first)
        #expect(matches.count == 1)
        #expect(
            match.transactionHash.reverseOrder.hexadecimalString
                == ReusablePaymentAddressFixtureData.positiveTransactionID
        )
        #expect(match.qualifyingInputIndex == 0)
        #expect(
            match.senderPublicKey.compressedData.hexadecimalString
                == ReusablePaymentAddressFixtureData
                    .senderCompressedPublicKey
        )
        #expect(
            match.senderOutpoint.transactionHash.reverseOrder
                .hexadecimalString
                == "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        )
        #expect(match.senderOutpoint.outputIndex == 0)
        #expect(match.childIndex == 0)
        #expect(match.outputIndex == 0)
        #expect(match.output == decoded.transaction.outputs[0])
        #expect(match.output.value == 80_000)
        #expect(match.output.tokenData?.amount == 1)
        #expect(match.output.tokenData?.nft == nil)
        #expect(
            match.output.tokenData?.category.hexForDisplay
                == "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        )
        #expect(
            match.receivingPublicKey.compressedData.hexadecimalString
                == ReusablePaymentAddressFixtureData
                    .childCompressedPublicKey
        )
        #expect(match.receivingSigningKey.publicKey == match.receivingPublicKey)
        #expect(match.receivingSigningKey.description.contains("redacted"))
    }

    @Test("receiver skips a structurally valid prefix miss")
    func receiverSkipsStructurallyValidPrefixMiss() throws {
        let matches = try makeMatcher().matches(
            in: Data(
                hexadecimalString:
                    ReusablePaymentAddressFixtureData
                        .prefixMissTransactionHex
            ),
            for: ReusablePaymentAddressFixtureData.makeAddress(),
            scanSigningKey:
                ReusablePaymentAddressFixtureData.makeScanSigningKey(),
            spendSigningKey:
                ReusablePaymentAddressFixtureData.makeSpendSigningKey()
        )

        #expect(matches.isEmpty)
    }

    @Test("receiver skips uncompressed input public keys")
    func receiverSkipsUncompressedInputPublicKeys() throws {
        let matches = try makeMatcher().matches(
            in: Data(
                hexadecimalString:
                    ReusablePaymentAddressFixtureData
                        .uncompressedInputTransactionHex
            ),
            for: ReusablePaymentAddressFixtureData.makeAddress(),
            scanSigningKey:
                ReusablePaymentAddressFixtureData.makeScanSigningKey(),
            spendSigningKey:
                ReusablePaymentAddressFixtureData.makeSpendSigningKey()
        )

        #expect(matches.isEmpty)
    }

    @Test("receiver rejects trailing transaction bytes")
    func receiverRejectsTrailingTransactionBytes() throws {
        var rawTransaction = try Data(
            hexadecimalString:
                ReusablePaymentAddressFixtureData.positiveTransactionHex
        )
        rawTransaction.append(0)

        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .invalidSerializedTransaction
        ) {
            _ = try makeMatcher().matches(
                in: rawTransaction,
                for: ReusablePaymentAddressFixtureData.makeAddress(),
                scanSigningKey:
                    ReusablePaymentAddressFixtureData.makeScanSigningKey(),
                spendSigningKey:
                    ReusablePaymentAddressFixtureData.makeSpendSigningKey()
            )
        }
    }

    @Test("receiver rejects a scan signing key from another address")
    func receiverRejectsMismatchedScanSigningKey() throws {
        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .scanSigningKeyMismatch
        ) {
            _ = try makeMatcher().matches(
                in: Data(
                    hexadecimalString:
                        ReusablePaymentAddressFixtureData
                            .positiveTransactionHex
                ),
                for: ReusablePaymentAddressFixtureData.makeAddress(),
                scanSigningKey:
                    ReusablePaymentAddressFixtureData.makeSigningKey(
                        scalar: 8
                    ),
                spendSigningKey:
                    ReusablePaymentAddressFixtureData.makeSpendSigningKey()
            )
        }
    }

    @Test("receiver rejects a spend signing key from another address")
    func receiverRejectsMismatchedSpendSigningKey() throws {
        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .spendSigningKeyMismatch
        ) {
            _ = try makeMatcher().matches(
                in: Data(
                    hexadecimalString:
                        ReusablePaymentAddressFixtureData
                            .positiveTransactionHex
                ),
                for: ReusablePaymentAddressFixtureData.makeAddress(),
                scanSigningKey:
                    ReusablePaymentAddressFixtureData.makeScanSigningKey(),
                spendSigningKey:
                    ReusablePaymentAddressFixtureData.makeSigningKey(
                        scalar: 14
                    )
            )
        }
    }

    @Test("receiver refuses legacy Electron Cash paycodes")
    func receiverRefusesLegacyElectronCashPaycodes() throws {
        let legacy = try OpalBase.ReusablePaymentAddress.Codec().parse(
            ReusablePaymentAddressFixtureData.legacyPaycodeMainnet,
            network: .mainnet
        )

        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error.unsupportedProfile(
                .legacyElectronCash
            )
        ) {
            _ = try makeMatcher().matches(
                in: Data(
                    hexadecimalString:
                        ReusablePaymentAddressFixtureData
                            .positiveTransactionHex
                ),
                for: legacy,
                scanSigningKey:
                    ReusablePaymentAddressFixtureData.makeScanSigningKey(),
                spendSigningKey:
                    ReusablePaymentAddressFixtureData.makeSpendSigningKey()
            )
        }
    }

    private func makeMatcher()
        -> OpalBase.ReusablePaymentAddress.Matcher
    {
        OpalBase.ReusablePaymentAddress.Matcher()
    }
}
