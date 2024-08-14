import XCTest
@testable import OpalBase

final class TransactionTests: XCTestCase {
    func testGeneratePreimage() throws {
        let index: Int = 0
        let hashType: Transaction.HashType = .all(anyoneCanPay: false)
        let outputBeingSpent = Transaction.Output(
            value: 6540,
            lockingScript: Data(hex: "76a914931983ce89e409f42fba9e39b42e826529b891a788ac")
        )
        
        let transaction = Transaction(
            version: 2,
            inputs: [
                Transaction.Input(previousTransactionHash: .init(dataFromBlockExplorer: Data(hex: "10cde50b23c8b719b7d27d6df49f38403ec5bad1eba191b18f8ff0aee662628a")),
                                  previousTransactionOutputIndex: 1,
                                  unlockingScript: .init(),
                                  sequence: 4294967295)
            ],
            outputs: [
                Transaction.Output(
                    value: 600,
                    lockingScript: Data(hex: "76a914327286de44846065b8812dbef68ec1dab38834f088ac")
                ),
                Transaction.Output(
                    value: 5714,
                    lockingScript: Data(hex: "76a914b8759fb3cbe426c6a47365c2cce3a900d18a046888ac")
                )
            ],
            lockTime: 0
        )
        
        // Call the generatePreimage function
        let preimage = transaction.generatePreimage(for: index,
                                                    hashType: hashType,
                                                    outputBeingSpent: outputBeingSpent)
        
        // Expected preimage based on the data provided
        let expectedPreimage = Data(hex: "02000000f62b7814b16e5ea5e2b6d520c161baeb7f7d38032bef2ce563063de73160b31f3bb13029ce7b1f559ef5e747fcac439f1455a2ec7c5f09b72290795e706650448a6262e6aef08f8fb191a1ebd1bac53e40389ff46d7dd2b719b7c8230be5cd10010000001976a914931983ce89e409f42fba9e39b42e826529b891a788ac8c19000000000000ffffffff6adf18b4dee6a30501a2f0c0f62e14faefffd5a48e59daee77f25e3cc0b9442e0000000041000000")
        
        // Assert that the generated preimage matches the expected preimage
        XCTAssertEqual(preimage, expectedPreimage, "The generated preimage does not match the expected preimage.")
    }
}
