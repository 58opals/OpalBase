// OpalBase+Account~Command~BroadcastAndConfirmation.swift

import Foundation

// MARK: - Broadcast
extension _OpalBase.Account {
    public func broadcast(_ transaction: OpalBase.Transaction,
                          via handler: OpalBase.Network.TransactionHandling) async throws -> OpalBase.Transaction.HashModel {
        do {
            return try await handler.broadcast(transaction: transaction)
        } catch {
            throw OpalBase.Account.Error.broadcastFailed(error)
        }
    }
    
    public func monitorConfirmations(for transactionHash: OpalBase.Transaction.HashModel,
                                     via handler: OpalBase.Network.TransactionHandling,
                                     pollInterval: Duration = .seconds(5)) -> AsyncThrowingStream<UInt?, Swift.Error> {
        let identifier = transactionHash.reverseOrder.hexadecimalString
        let fallbackInterval: Duration = .milliseconds(100)
        let effectiveInterval = pollInterval > .zero ? pollInterval : fallbackInterval
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                enum ConfirmationStatus: Equatable {
                    case initial
                    case value(UInt?)
                }
                
                var lastStatus: ConfirmationStatus = .initial
                
                while !Task.isCancelled {
                    do {
                        try Task.checkCancellation()
                        
                        let confirmations: UInt?
                        do {
                            confirmations = try await handler.fetchConfirmations(forTransactionIdentifier: identifier)
                        } catch {
                            throw OpalBase.Account.Error.confirmationQueryFailed(error)
                        }
                        
                        let currentStatus: ConfirmationStatus = .value(confirmations)
                        if lastStatus != currentStatus {
                            continuation.yield(confirmations)
                            lastStatus = currentStatus
                        }
                        
                        do {
                            try await Task.sleep(for: effectiveInterval)
                        } catch {
                            if error.isCancellationError {
                                continuation.finish()
                                return
                            }
                            throw error
                        }
                    } catch {
                        if error.isCancellationError {
                            continuation.finish()
                            return
                        }
                        if let accountError = error as? OpalBase.Account.Error {
                            continuation.finish(throwing: accountError)
                            return
                        }
                        continuation.finish(throwing: OpalBase.Account.Error.confirmationQueryFailed(error))
                        return
                    }
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
