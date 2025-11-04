// Network+TransactionHandling_.swift

import Foundation

extension Network {
    public typealias TransactionHandling = TransactionBroadcasting & TransactionConfirming
    
    public protocol TransactionBroadcasting: Sendable {
        func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String
    }
    
    public protocol TransactionConfirming: Sendable {
        func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt?
    }
}
