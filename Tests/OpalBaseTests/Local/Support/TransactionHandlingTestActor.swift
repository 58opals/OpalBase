// TransactionHandlingTestActor.swift

import Foundation
@testable import OpalBase

actor TransactionHandlingTestActor: OpalBase.Network.TransactionHandling {
    private let broadcastResult: Result<String, Swift.Error>
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [OpalBase.Transaction.HashModel: OpalBase.Network.TransactionConfirmationStatus]

    private var broadcastedTransactions: [String] = .init()

    init(
        broadcastResult: Result<String, Swift.Error>,
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [OpalBase.Transaction.HashModel: OpalBase.Network.TransactionConfirmationStatus] = .init()
    ) {
        self.broadcastResult = broadcastResult
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
        broadcastedTransactions.append(rawTransactionHexadecimal)
        switch broadcastResult {
        case .success(let identifier):
            return identifier
        case .failure(let error):
            throw error
        }
    }

    func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
        confirmationsByIdentifier[transactionIdentifier] ?? nil
    }

    func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.HashModel) async throws -> OpalBase.Network.TransactionConfirmationStatus {
        statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readBroadcastedTransactions() -> [String] {
        broadcastedTransactions
    }
}

