// TransactionHandlingTestActor.swift

import Foundation
@testable import OpalBase

actor TransactionHandlingTestActor: OpalBase.Network.TransactionHandling {
    private let broadcastHandler: @Sendable (String) async throws -> String
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [OpalBase.Transaction.Hash: OpalBase.Network.TransactionConfirmationStatus]

    private var broadcastedTransactions: [String] = .init()

    init(
        broadcastResult: Result<String, Swift.Error>,
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [OpalBase.Transaction.Hash: OpalBase.Network.TransactionConfirmationStatus] = .init()
    ) {
        self.broadcastHandler = { _ in
            switch broadcastResult {
            case .success(let identifier):
                return identifier
            case .failure(let error):
                throw error
            }
        }
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    init(
        deriveBroadcastTransactionHash: Bool,
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [OpalBase.Transaction.Hash: OpalBase.Network.TransactionConfirmationStatus] = .init()
    ) {
        self.broadcastHandler = { rawTransactionHexadecimal in
            guard deriveBroadcastTransactionHash else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Broadcast result is unavailable."
                )
            }
            let rawTransactionData = try Data(hexadecimalString: rawTransactionHexadecimal)
            let transactionHash = OpalBase.Transaction.Hash(
                naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
            )
            return transactionHash.reverseOrder.hexadecimalString
        }
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
        broadcastedTransactions.append(rawTransactionHexadecimal)
        return try await broadcastHandler(rawTransactionHexadecimal)
    }

    func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
        confirmationsByIdentifier[transactionIdentifier] ?? nil
    }

    func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus {
        statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readBroadcastedTransactions() -> [String] {
        broadcastedTransactions
    }
}
