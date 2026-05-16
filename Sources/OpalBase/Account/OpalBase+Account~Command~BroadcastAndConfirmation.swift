// OpalBase+Account~Command~BroadcastAndConfirmation.swift

import Foundation

// MARK: - Broadcast
extension _OpalBase.Account {
    public func broadcast(_ transaction: OpalBase.Transaction,
                          via handler: OpalBase.Network.TransactionClient) async throws -> OpalBase.Transaction.Hash {
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("transaction_broadcast"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.inputCount, transaction.inputs.count),
                OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.outputCount, transaction.outputs.count)
            ]
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.transactionBroadcastStarted,
                category: OpalBase.Diagnostics.Categories.transaction,
                fields: fields
            )
            do {
                let hash = try await handler.broadcast(transaction: transaction)
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.transactionBroadcastSucceeded,
                    category: OpalBase.Diagnostics.Categories.transaction,
                    fields: fields
                )
                return hash
            } catch {
                let accountError = OpalBase.Account.Error.broadcastFailed(error)
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.transactionBroadcastFailed,
                    category: OpalBase.Diagnostics.Categories.transaction,
                    fields: fields + OpalBaseDiagnostics.errorFields(
                        for: accountError,
                        fallback: OpalBase.Diagnostics.ErrorCodes.accountBroadcastFailed
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
