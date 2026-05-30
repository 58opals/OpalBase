// OpalBase+Account~Command~BroadcastAndConfirmation.swift

import Foundation
import OpalDiagnostics

// MARK: - Broadcast
extension _OpalBase.Account {
    public func broadcast(_ transaction: OpalBase.Transaction,
                          via handler: OpalBase.Network.TransactionClient) async throws -> OpalBase.Transaction.Hash {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("transaction_broadcast"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inputCount, transaction.inputs.count),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, transaction.outputs.count)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.transactionBroadcastStarted,
                category: OpalDiagnostics.Category.transaction,
                fields: fields
            )
            do {
                let hash = try await handler.broadcast(transaction: transaction)
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionBroadcastSucceeded,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields
                )
                return hash
            } catch {
                if error.isCancellationError {
                    throw error
                }
                let accountError = OpalBase.Account.Error.broadcastFailed(error)
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionBroadcastFailed,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields + OpalDiagnostics.Field.errorFields(
                        for: accountError,
                        fallback: OpalDiagnostics.ErrorCode.accountBroadcastFailed
                    )
                )
                throw accountError
            }
        }
    }
    
    public func monitorConfirmations(for transactionHash: OpalBase.Transaction.Hash,
                                     via handler: OpalBase.Network.TransactionClient,
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
                            if error.isCancellationError {
                                throw error
                            }
                            throw OpalBase.Account.Error.confirmationQueryFailed(error)
                        }
                        
                        let currentStatus: ConfirmationStatus = .value(confirmations)
                        if lastStatus != currentStatus {
                            continuation.yield(confirmations)
                            lastStatus = currentStatus
                        }
                        
                        try await Task.sleep(for: effectiveInterval)
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
