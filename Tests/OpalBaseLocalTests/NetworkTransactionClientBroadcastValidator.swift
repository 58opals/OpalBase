// NetworkTransactionClientBroadcastValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.TransactionClient broadcast", .tags(.unit, .network, .transaction))
struct NetworkTransactionClientBroadcastValidator {
    @Test("broadcast returns the hash derived from the submitted transaction", arguments: BroadcastInvocationKind.allCases)
    private func broadcastReturnsDerivedTransactionHash(kind: BroadcastInvocationKind) async throws {
        let transaction = makeTransaction()
        let rawTransactionData = try transaction.encode()
        let expectedHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        let client = makeTransactionClient(returning: expectedHash.reverseOrder.hexadecimalString)

        let hash = try await broadcast(
            using: kind,
            client: client,
            transaction: transaction,
            rawTransactionData: rawTransactionData
        )

        #expect(hash == expectedHash)
    }

    @Test("broadcast rejects a mismatched returned transaction hash", arguments: BroadcastInvocationKind.allCases)
    private func broadcastRejectsMismatchedTransactionHash(kind: BroadcastInvocationKind) async throws {
        let transaction = makeTransaction()
        let rawTransactionData = try transaction.encode()
        let wrongHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x99, count: 32))
        let client = makeTransactionClient(returning: wrongHash.reverseOrder.hexadecimalString)
        let expectedError = try makeBroadcastMismatchError(transaction: transaction, actualHash: wrongHash)

        await #expect(throws: expectedError) {
            _ = try await broadcast(
                using: kind,
                client: client,
                transaction: transaction,
                rawTransactionData: rawTransactionData
            )
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

    private func makeBroadcastMismatchError(
        transaction: OpalBase.Transaction,
        actualHash: OpalBase.Transaction.Hash
    ) throws -> OpalBase.Network.Error {
        OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Broadcast transaction hash mismatch",
            metadata: [
                "expected": OpalBase.Transaction.Hash(
                    naturalOrder: OpalCryptoAdapter.hash256(try transaction.encode())
                ).reverseOrder.hexadecimalString,
                "actual": actualHash.reverseOrder.hexadecimalString
            ]
        )
    }

    private func broadcast(
        using kind: BroadcastInvocationKind,
        client: OpalBase.Network.TransactionClient,
        transaction: OpalBase.Transaction,
        rawTransactionData: Data
    ) async throws -> OpalBase.Transaction.Hash {
        switch kind {
        case .transaction:
            return try await client.broadcast(transaction: transaction)
        case .rawTransaction:
            let transactionIdentifier = try await client.broadcastTransaction(
                rawTransactionHexadecimal: rawTransactionData.hexadecimalString
            )
            return try OpalBase.Network.decodeTransactionHash(
                from: transactionIdentifier,
                label: "broadcast transaction identifier"
            )
        }
    }

    private enum BroadcastInvocationKind: String, CaseIterable, CustomStringConvertible, Sendable {
        case transaction
        case rawTransaction

        var description: String { rawValue }
    }
}
