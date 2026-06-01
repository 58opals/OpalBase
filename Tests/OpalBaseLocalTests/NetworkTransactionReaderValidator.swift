// NetworkTransactionReaderValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Network.TransactionReader", .tags(.unit, .network, .transaction))
struct NetworkTransactionReaderValidator {
    @Test("transaction reader normalizes sliced raw transaction data")
    func transactionReaderNormalizesSlicedRawTransactionData() async throws {
        let rawTransactionData = Data([0x01, 0x02, 0x03])
        let paddedRawTransactionData = Data([0x00]) + rawTransactionData
        let slicedRawTransactionData = paddedRawTransactionData[
            paddedRawTransactionData.index(after: paddedRawTransactionData.startIndex)...
        ]
        let reader = OpalBase.Network.TransactionReader { _ in
            slicedRawTransactionData
        }

        let fetchedData = try await reader.fetchRawTransaction(
            for: .init(naturalOrder: Data(repeating: 0x11, count: 32))
        )

        #expect(slicedRawTransactionData.startIndex != rawTransactionData.startIndex)
        #expect(fetchedData == rawTransactionData)
        #expect(fetchedData.startIndex == rawTransactionData.startIndex)
    }
}
