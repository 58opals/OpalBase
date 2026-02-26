import Foundation
@testable import OpalBase

actor TransactionHandlingTestActor: NetworkModel.TransactionHandling {
    private let broadcastResult: Result<String, Swift.Error>
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [TransactionModel.HashModel: NetworkModel.TransactionConfirmationStatusModel]

    private var broadcastedTransactions: [String] = .init()

    init(
        broadcastResult: Result<String, Swift.Error>,
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [TransactionModel.HashModel: NetworkModel.TransactionConfirmationStatusModel] = .init()
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

    func fetchConfirmationStatus(for transactionHash: TransactionModel.HashModel) async throws -> NetworkModel.TransactionConfirmationStatusModel {
        statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readBroadcastedTransactions() -> [String] {
        broadcastedTransactions
    }
}
