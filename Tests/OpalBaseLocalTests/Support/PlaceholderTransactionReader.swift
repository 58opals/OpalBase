// PlaceholderTransactionReader.swift

import Foundation
@testable import OpalBase

struct PlaceholderTransactionReader: OpalBase.Network.TransactionReadableClient {
    func fetchRawTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> Data {
        throw PlaceholderNetworkError.notImplemented
    }
}
