// OpalBase.Network+TransactionBroadcastClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol TransactionBroadcastClient: Sendable {
        func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String
    }
}
