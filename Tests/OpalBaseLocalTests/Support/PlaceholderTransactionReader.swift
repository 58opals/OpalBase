// PlaceholderTransactionReader.swift

import Foundation
@testable import OpalBase
@testable import OpalBaseCore

struct PlaceholderTransactionReader: OpalBase.Network.TransactionReadableClient {
    func fetchRawTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> Data {
        throw PlaceholderNetworkError.notImplemented
    }
}
