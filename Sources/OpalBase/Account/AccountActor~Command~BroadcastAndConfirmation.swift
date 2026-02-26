// AccountActor~Command~BroadcastAndConfirmation.swift

import Foundation

// MARK: - Broadcast
extension AccountActor {
    public func broadcast(_ transaction: TransactionModel,
                          via handler: NetworkModel.TransactionHandling) async throws -> TransactionModel.HashModel {
        do {
            return try await handler.broadcast(transaction: transaction)
        } catch {
            throw AccountActor.Error.broadcastFailed(error)
        }
    }
    
    public func monitorConfirmations(for transactionHash: TransactionModel.HashModel,
                                     via handler: NetworkModel.TransactionHandling,
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
                            throw AccountActor.Error.confirmationQueryFailed(error)
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
                        if let accountError = error as? AccountActor.Error {
                            continuation.finish(throwing: accountError)
                            return
                        }
                        continuation.finish(throwing: AccountActor.Error.confirmationQueryFailed(error))
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
