// TransactionHashValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction.Hash", .tags(.unit))
struct TransactionHashValidator {
    @Test("natural-order initializer normalizes sliced data")
    func naturalOrderInitializerNormalizesSlicedData() {
        let hashData = Data(repeating: 0x33, count: OpalBase.Transaction.Hash.expectedByteCount)
        let paddedData = Data([0x00]) + hashData + Data([0xff])
        let slicedData = paddedData[
            paddedData.index(after: paddedData.startIndex)..<paddedData.index(before: paddedData.endIndex)
        ]

        let hash = OpalBase.Transaction.Hash(naturalOrder: slicedData)

        #expect(slicedData.startIndex != hashData.startIndex)
        #expect(hash.naturalOrder == hashData)
        #expect(hash.naturalOrder.startIndex == hashData.startIndex)
    }
}
