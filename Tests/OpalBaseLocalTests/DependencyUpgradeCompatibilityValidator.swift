// DependencyUpgradeCompatibilityValidator.swift

import Foundation
import OpalCrypto
import OpalDiagnostics
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("Dependency upgrade compatibility", .tags(.unit))
struct DependencyUpgradeCompatibilityValidator {
    @Test("legacy-address Base58 budget accepts 25 bytes and rejects 26")
    func enforceLegacyAddressBase58DecodeBudget() {
        let accepted = Data(repeating: 0x01, count: 25)
        let rejected = Data(repeating: 0x01, count: 26)

        #expect(
            OpalCryptoAdapter.decodeBase58(
                OpalCrypto.Encoding.encodeBase58(accepted),
                maximumDecodedByteCount: 25
            ) == accepted
        )
        #expect(
            OpalCryptoAdapter.decodeBase58(
                OpalCrypto.Encoding.encodeBase58(rejected),
                maximumDecodedByteCount: 25
            ) == nil
        )
    }

    @Test("extended-key Base58 budget accepts 82 bytes and rejects 83")
    func enforceExtendedKeyBase58DecodeBudget() {
        let accepted = Data(repeating: 0x01, count: 82)
        let rejected = Data(repeating: 0x01, count: 83)

        #expect(
            OpalCryptoAdapter.decodeBase58(
                OpalCrypto.Encoding.encodeBase58(accepted),
                maximumDecodedByteCount: 82
            ) == accepted
        )
        #expect(
            OpalCryptoAdapter.decodeBase58(
                OpalCrypto.Encoding.encodeBase58(rejected),
                maximumDecodedByteCount: 82
            ) == nil
        )
    }

    @Test("mnemonic word-count limit maps into OpalBase")
    func mapMnemonicWordCountLimit() {
        let phrase = Array(repeating: "abandon", count: 25).joined(separator: " ")
        let expectedError = OpalBase.Key.Mnemonic.Error.wordCountExceedsMaximum(maximum: 24)

        #expect(throws: expectedError) {
            _ = try OpalBase.Key.Mnemonic(phrase: phrase)
        }
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: expectedError) == .keyInvalid)
    }

    @Test("mnemonic phrase-byte limit maps into OpalBase")
    func mapMnemonicPhraseByteCountLimit() {
        let phrase = String(repeating: "a", count: 8_193)
        let expectedError = OpalBase.Key.Mnemonic.Error.phraseByteCountExceedsMaximum(
            maximum: 8_192,
            actual: 8_193
        )

        #expect(throws: expectedError) {
            _ = try OpalBase.Key.Mnemonic(phrase: phrase)
        }
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: expectedError) == .keyInvalid)
    }

    @Test("mnemonic word-byte limit maps into OpalBase")
    func mapMnemonicWordByteCountLimit() {
        let oversizedWord = String(repeating: "a", count: 257)
        let phrase = ([oversizedWord] + Array(repeating: "abandon", count: 11))
            .joined(separator: " ")
        let expectedError = OpalBase.Key.Mnemonic.Error.wordByteCountExceedsMaximum(
            maximum: 256,
            actual: 257
        )

        #expect(throws: expectedError) {
            _ = try OpalBase.Key.Mnemonic(phrase: phrase)
        }
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: expectedError) == .keyInvalid)
    }

    @Test("invalid Fulcrum configuration maps to an OpalBase transport error")
    func translateInvalidFulcrumConfiguration() {
        let reason = "maximumMessageSize must be greater than zero."
        let translated = OpalBase.Network.FulcrumErrorTranslator.translate(
            SwiftFulcrum.Client.Error.client(.invalidConfiguration(reason))
        )

        #expect(
            translated == OpalBase.Network.Error(
                reason: .transport,
                message: "Invalid client configuration: \(reason)"
            )
        )
    }

    @Test("numeric diagnostic fields are explicitly public")
    func markNumericDiagnosticFieldsPublic() {
        let fields = [
            OpalDiagnostics.Field.publicValue("integer", -1),
            OpalDiagnostics.Field.publicValue("unsigned_integer", UInt64.max),
            OpalDiagnostics.Field.publicValue("boolean", true)
        ]

        #expect(fields.allSatisfy { $0.privacy == .public })
    }
}
