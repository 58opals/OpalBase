// Network+TransactionBroadcastClient_.swift

import Foundation

extension Network {
    public protocol TransactionBroadcastClient: Sendable {
        func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String
    }
}
