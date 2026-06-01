// TransactionInputValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction.Input", .tags(.unit, .transaction))
struct TransactionInputValidator {
    @Test("initializer normalizes sliced unlocking script")
    func initializerNormalizesSlicedUnlockingScript() {
        let unlockingScript = Data([0x41, 0x01, 0x02])
        let paddedData = Data([0xff]) + unlockingScript
        let slicedUnlockingScript = paddedData[paddedData.index(after: paddedData.startIndex)...]
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: slicedUnlockingScript
        )

        #expect(slicedUnlockingScript.startIndex != unlockingScript.startIndex)
        #expect(input.unlockingScript == unlockingScript)
        #expect(input.unlockingScript.startIndex == unlockingScript.startIndex)
    }
}
