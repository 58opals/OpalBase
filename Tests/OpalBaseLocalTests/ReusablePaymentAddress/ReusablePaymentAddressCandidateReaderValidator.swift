// ReusablePaymentAddressCandidateReaderValidator.swift

import Testing
@testable import OpalBase

@Suite("Reusable payment address candidate reader", .tags(.unit, .network))
struct ReusablePaymentAddressCandidateReaderValidator {
    @Test("candidate reader forwards prefix and starting height")
    func forwardPrefixAndStartingHeight() async throws {
        let expectedPrefix = try ReusablePaymentAddressFixtureData.makePrefix()
        let expectedTransaction = try ReusablePaymentAddressFixtureData.makeCandidateTransaction()
        let reader = OpalBase.Network.ReusablePaymentAddressCandidateReader { prefix, blockHeight in
            #expect(prefix == expectedPrefix)
            #expect(blockHeight == 120)
            return [expectedTransaction]
        }

        let transactions = try await reader.fetchCandidateTransactions(
            matching: expectedPrefix,
            sinceBlockHeight: 120
        )

        #expect(transactions == [expectedTransaction])
    }

    @Test("candidate reader rejects negative starting heights before transport")
    func rejectNegativeStartingHeight() async throws {
        let prefix = try ReusablePaymentAddressFixtureData.makePrefix()
        let reader = OpalBase.Network.ReusablePaymentAddressCandidateReader { _, _ in
            Issue.record("transport closure should not run for invalid block heights")
            return []
        }

        await #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(-1)) {
            _ = try await reader.fetchCandidateTransactions(
                matching: prefix,
                sinceBlockHeight: -1
            )
        }
    }
}
