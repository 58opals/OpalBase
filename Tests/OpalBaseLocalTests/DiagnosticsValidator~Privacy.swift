// DiagnosticsValidator~Privacy.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

extension DiagnosticsValidator {
    @Test("recent diagnostics redact sensitive values and use safe field names")
    func recentDiagnosticsRedactSensitiveValuesAndUseSafeFieldNames() async throws {
        let mnemonic = try AccountTestFixtures.makeMnemonic()
        let result = try await OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            let wallet = try OpalBase.Wallet(mnemonic: mnemonic)
            try await wallet.addAccount(unhardenedIndex: 0)
            let account = try await wallet.fetchAccount(at: 0)
            let entry = try await account.reserveNextReceivingDerivedAddress()
            let fullAddress = entry.address.generateString(withPrefix: true)
            let sensitiveValues = [
                AccountTestFixtures.mnemonicWords.joined(separator: " "),
                try mnemonic.deriveSeed().rawRepresentation.hexadecimalString,
                "private key 000102030405060708090a0b0c0d0e0f",
                "L1aW4aubDFB7yfras2S1mN3bqg9w7L3w5h8QYV4AExampleWIF",
                fullAddress,
                "0100000001abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                #"{"contract":"raw","oracle":"message","redeemScript":"51"}"#,
                "oracle message payload",
                "oracle signature payload",
                "redeem script payload",
                "raw proof material payload",
                "3045022100signaturepayload",
                "02publickeypayload",
                "opalclaim:share-code-payload",
                "claimable secret payload",
                "fusion participant material payload"
            ]

            OpalDiagnostics.record(
                OpalDiagnostics.Event.walletCreateStarted,
                category: OpalDiagnostics.Category.wallet,
                fields: sensitiveValues.enumerated().map { index, value in
                    OpalDiagnostics.Field.privateValue("private_payload_\(index)", value)
                }
            )

            return (records: OpalDiagnostics.recentRecords, sensitiveValues: sensitiveValues)
        }

        let renderedRecords = render(result.records)
        for sensitiveValue in result.sensitiveValues {
            #expect(renderedRecords.contains(sensitiveValue) == false)
        }
    }

    @Test(
        "diagnostic field names avoid sensitive vocabulary",
        arguments: forbiddenFieldNameFragments
    )
    func diagnosticFieldNamesAvoidSensitiveVocabulary(_ forbiddenNameFragment: String) {
        let fieldNames = OpalDiagnostics.Field.Name.all.joined(separator: " ")
        #expect(fieldNames.contains(forbiddenNameFragment) == false)
    }

    private static let forbiddenFieldNameFragments = [
        "mnemonic", "seed", "private_key", "wif", "full_address", "raw_transaction",
        "contract_json", "oracle_message", "oracle_signature", "redeem_script", "raw_proof",
        "signature", "public_key", "share_code", "claimable_secret", "fusion_participant"
    ]
}
