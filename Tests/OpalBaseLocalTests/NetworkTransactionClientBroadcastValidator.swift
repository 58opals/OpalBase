// NetworkTransactionClientBroadcastValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.TransactionClient broadcast", .tags(.unit, .network, .transaction))
struct NetworkTransactionClientBroadcastValidator {
    @Test("broadcast returns the hash derived from the serialized transaction")
    func broadcastReturnsDerivedTransactionHash() async throws {
        let transaction = makeTransaction()
        let rawTransactionData = try transaction.encode()
        let expectedHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        let client = makeTransactionClient(returning: expectedHash.reverseOrder.hexadecimalString)

        let hash = try await client.broadcast(transaction: transaction)

        #expect(hash == expectedHash)
    }

    @Test("broadcast rejects a mismatched returned transaction hash")
    func broadcastRejectsMismatchedTransactionHash() async throws {
        let transaction = makeTransaction()
        let wrongHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x99, count: 32))
        let client = makeTransactionClient(returning: wrongHash.reverseOrder.hexadecimalString)

        await #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Broadcast transaction hash mismatch",
            metadata: [
                "expected": OpalBase.Transaction.Hash(
                    naturalOrder: OpalCryptoAdapter.hash256(try transaction.encode())
                ).reverseOrder.hexadecimalString,
                "actual": wrongHash.reverseOrder.hexadecimalString
            ]
        )) {
            _ = try await client.broadcast(transaction: transaction)
        }
    }

    private func makeTransactionClient(returning transactionIdentifier: String) -> OpalBase.Network.TransactionClient {
        OpalBase.Network.TransactionClient(
            broadcastTransaction: { _ in transactionIdentifier },
            fetchConfirmations: { _ in nil },
            fetchConfirmationStatus: { transactionHash in
                .init(
                    transactionHash: transactionHash,
                    transactionHeight: nil,
                    tipHeight: 0,
                    confirmations: nil
                )
            }
        )
    }

    private func makeTransaction() -> OpalBase.Transaction {
        OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0x11, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x51])
                )
            ],
            outputs: [
                .init(
                    value: 1_000,
                    lockingScript: Data([0x51])
                )
            ],
            lockTime: 0
        )
    }
}
