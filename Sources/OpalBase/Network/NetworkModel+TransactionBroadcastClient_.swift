// NetworkModel+TransactionBroadcastClient_.swift

import Foundation

extension NetworkModel {
    public protocol TransactionBroadcastClient: Sendable {
        func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String
    }
}
