// TransactionConfirmationClientTestActor.swift

import Foundation
@testable import OpalBase

actor TransactionConfirmationClientTestActor: OpalBase.Network.TransactionConfirmationClient {
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [OpalBase.Transaction.HashModel: OpalBase.Network.TransactionConfirmationStatus]

    private var confirmationIdentifierRequests: [String] = .init()
    private var confirmationStatusRequests: [OpalBase.Transaction.HashModel] = .init()

    init(
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [OpalBase.Transaction.HashModel: OpalBase.Network.TransactionConfirmationStatus] = .init()
    ) {
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
        confirmationIdentifierRequests.append(transactionIdentifier)
        return confirmationsByIdentifier[transactionIdentifier] ?? nil
    }

    func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.HashModel) async throws -> OpalBase.Network.TransactionConfirmationStatus {
        confirmationStatusRequests.append(transactionHash)
        return statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readConfirmationStatusRequests() -> [OpalBase.Transaction.HashModel] {
        confirmationStatusRequests
    }
}
