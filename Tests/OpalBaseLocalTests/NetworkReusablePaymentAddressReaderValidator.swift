// NetworkReusablePaymentAddressReaderValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Transport-neutral reusable payment address reader", .tags(.unit, .network))
struct NetworkReusablePaymentAddressReaderValidator {
    @Test("reader forwards bounded half-open ranges and skips empty ranges")
    func forwardBoundedHalfOpenRanges() async throws {
        let hash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x31, count: 32)
        )
        let reference = OpalBase.ReusablePaymentAddress
            .ConfirmedTransactionReference(
                transactionHash: hash,
                blockHeight: 11
            )
        let actor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [reference]
        )
        let reader = OpalBase.Network.ReusablePaymentAddressReader(
            fetchConfirmedTransactionReferences: { prefix, heights in
                try await actor.fetchConfirmedTransactionReferences(
                    matching: prefix,
                    in: heights
                )
            },
            fetchMempoolTransactionReferences: { prefix in
                await actor.fetchMempoolTransactionReferences(
                    matching: prefix
                )
            }
        )
        let prefix = try ReusablePaymentAddressFixtureData.makeAddress()
            .filterPrefix

        let fetched = try await reader.fetchConfirmedTransactionReferences(
            matching: prefix,
            in: 10..<12
        )
        let empty = try await reader.fetchConfirmedTransactionReferences(
            matching: prefix,
            in: 12..<12
        )

        #expect(fetched == [reference])
        #expect(empty.isEmpty)
        #expect(await actor.readConfirmedRanges() == [10..<12])
    }
}
