// TransactionReaderClientTestActor.swift

import SwiftFulcrum
@testable import OpalBase

actor TransactionReaderClientTestActor: OpalBase.Network.Fulcrum.TransactionReaderClient {
    private let rawTransactionHex: String
    private let verboseTransaction: SwiftFulcrum.Response.Blockchain.Transaction.Verbose
    private let rawError: Swift.Error?
    private let verboseError: Swift.Error?
    private var rawRequests: [String] = []
    private var verboseRequests: [String] = []

    init(
        rawTransactionHex: String,
        verboseTransaction: SwiftFulcrum.Response.Blockchain.Transaction.Verbose,
        rawError: Swift.Error? = nil,
        verboseError: Swift.Error? = nil
    ) {
        self.rawTransactionHex = rawTransactionHex
        self.verboseTransaction = verboseTransaction
        self.rawError = rawError
        self.verboseError = verboseError
    }

    func fetchRawTransaction(
        transactionHash: String,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> String {
        rawRequests.append(transactionHash)
        if let rawError {
            throw rawError
        }
        return rawTransactionHex
    }

    func fetchVerboseTransaction(
        transactionHash: String,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.Transaction.Verbose {
        verboseRequests.append(transactionHash)
        if let verboseError {
            throw verboseError
        }
        return verboseTransaction
    }

    func readRawFetchCount() -> Int {
        rawRequests.count
    }

    func readVerboseFetchCount() -> Int {
        verboseRequests.count
    }

    func readLastRawTransactionHash() -> String? {
        rawRequests.last
    }

    func readLastVerboseTransactionHash() -> String? {
        verboseRequests.last
    }
}
