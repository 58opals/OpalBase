// ReusablePaymentAddressPaymentValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Cash Code payment derivation", .tags(.unit))
struct ReusablePaymentAddressPaymentValidator {
    @Test("sender derives the independent compressed P2PKH vector")
    func senderDerivesIndependentCompressedP2PKHVector() throws {
        let decoded = try ReusablePaymentAddressFixtureData.decodeTransaction(
            hexadecimalString:
                ReusablePaymentAddressFixtureData.positiveTransactionHex
        )
        let input = try #require(decoded.transaction.inputs.first)
        let cashCode = try ReusablePaymentAddressFixtureData.makeAddress()

        let payment = try cashCode.derivePayment(
            from: ReusablePaymentAddressFixtureData.makeSenderSigningKey(),
            spending: .init(input)
        )

        #expect(payment.childIndex == 0)
        #expect(
            payment.receivingPublicKey.compressedData.hexadecimalString
                == ReusablePaymentAddressFixtureData
                    .childCompressedPublicKey
        )
        #expect(
            payment.lockingScript.hexadecimalString
                == ReusablePaymentAddressFixtureData.matchingLockingScript
        )
    }

    @Test("sender refuses legacy Electron Cash paycodes")
    func senderRefusesLegacyElectronCashPaycodes() throws {
        let legacy = try OpalBase.ReusablePaymentAddress.Codec().parse(
            ReusablePaymentAddressFixtureData.legacyPaycodeMainnet,
            network: .mainnet
        )

        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error.unsupportedProfile(
                .legacyElectronCash
            )
        ) {
            _ = try legacy.derivePayment(
                from: ReusablePaymentAddressFixtureData
                    .makeSenderSigningKey(),
                spending: ReusablePaymentAddressFixtureData.makeOutpoint()
            )
        }
    }
}
