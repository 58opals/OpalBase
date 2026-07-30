// ReusablePaymentAddressVectorValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Cash Code conformance vector documents", .tags(.unit))
struct ReusablePaymentAddressVectorValidator {
    @Test("published vector documents retain their reviewed byte digests")
    func publishedVectorDocumentsRetainReviewedByteDigests() throws {
        let positive = try Self.loadDocument(
            named: "cash-code-v1-vectors.json"
        )
        let negative = try Self.loadDocument(
            named: "cash-code-v1-negative-vectors.json"
        )

        #expect(
            OpalCryptoAdapter.sha256(positive).hexadecimalString
                == "3946e880e9869e6e162eba8e9b7ff7397bb00c6610342210d2db5d2c2bcb5ba6"
        )
        #expect(
            OpalCryptoAdapter.sha256(negative).hexadecimalString
                == "e5fd12962f2065faa1bf2dd7a45e2e92a14d7704d3d2ee3a35041ca8bfff2d16"
        )
    }

    @Test("matcher ignores the valid vector designated at input 30")
    func matcherIgnoresValidVectorDesignatedAtInputThirty() throws {
        let document = try Self.loadJSONObject(
            named: "cash-code-v1-negative-vectors.json"
        )
        let vector = try #require(
            document["valid_31_input_limit_transaction"]
                as? [String: Any]
        )
        #expect(vector["input_count"] as? Int == 31)
        #expect(vector["designated_input_index"] as? Int == 30)
        #expect(vector["all_first_30_miss"] as? Bool == true)
        #expect(vector["input_30_matches"] as? Bool == true)
        let rawHexadecimal = try #require(vector["raw_hex"] as? String)

        let matches = try OpalBase.ReusablePaymentAddress.Matcher().matches(
            in: Data(hexadecimalString: rawHexadecimal),
            for: ReusablePaymentAddressFixtureData.makeAddress(),
            scanSigningKey:
                ReusablePaymentAddressFixtureData.makeScanSigningKey(),
            spendSigningKey:
                ReusablePaymentAddressFixtureData.makeSpendSigningKey()
        )

        #expect(matches.isEmpty)
    }

    private static func loadJSONObject(
        named name: String
    ) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(
            with: loadDocument(named: name)
        )
        return try #require(object as? [String: Any])
    }

    private static func loadDocument(named name: String) throws -> Data {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            repositoryRoot.deleteLastPathComponent()
        }
        return try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("docs", isDirectory: true)
                .appendingPathComponent(name)
        )
    }
}
