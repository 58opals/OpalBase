// Account+Payment.swift

import Foundation

extension Account {
    public struct Payment: Sendable {
        public struct Recipient: Sendable {
            public let address: Address
            public let amount: Satoshi
            
            public init(address: Address, amount: Satoshi) {
                self.address = address
                self.amount = amount
            }
        }
        
        public let recipients: [Recipient]
        public let feePerByte: UInt64
        public let coinSelection: Address.Book.CoinSelection
        public let allowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    feePerByte: UInt64 = Transaction.defaultFeeRate,
                    coinSelection: Address.Book.CoinSelection = .greedyLargestFirst,
                    allowDustDonation: Bool = false) {
            self.recipients = recipients
            self.feePerByte = feePerByte
            self.coinSelection = coinSelection
            self.allowDustDonation = allowDustDonation
        }
    }
}

extension Account {
    public func sendPayment(_ payment: Payment,
                            using session: Network.FulcrumSession,
                            retryPolicy: RequestRouter<Request>.RetryPolicy = .retry,
                            broadcaster: (@Sendable (String) async throws -> Void)? = nil) async throws -> Transaction.Hash {
        try await privacyShaper.scheduleSensitiveOperation {
            try await self.performSend(payment,
                                       using: session,
                                       retryPolicy: retryPolicy,
                                       broadcaster: broadcaster)
        }
    }
}

private extension Account {
    func performSend(_ payment: Payment,
                     using session: Network.FulcrumSession,
                     retryPolicy: RequestRouter<Request>.RetryPolicy,
                     broadcaster: (@Sendable (String) async throws -> Void)?) async throws -> Transaction.Hash {
        guard !payment.recipients.isEmpty else { throw Error.paymentHasNoRecipients }
        
        let broadcastClosure: @Sendable (String) async throws -> Void
        if let broadcaster {
            broadcastClosure = broadcaster
        } else {
            broadcastClosure = { rawTransaction in
                _ = try await session.broadcastTransaction(rawTransaction)
            }
        }
        
        let addressBook = self.addressBook
        
        var aggregateAmount: UInt64 = 0
        var recipientOutputs: [Transaction.Output] = .init()
        recipientOutputs.reserveCapacity(payment.recipients.count)
        
        for recipient in payment.recipients {
            let (updated, didOverflow) = aggregateAmount.addingReportingOverflow(recipient.amount.uint64)
            if didOverflow || updated > Satoshi.maximumSatoshi {
                throw Error.paymentExceedsMaximumAmount
            }
            aggregateAmount = updated
            recipientOutputs.append(Transaction.Output(value: recipient.amount.uint64,
                                                       address: recipient.address))
        }
        
        let targetAmount = try Satoshi(aggregateAmount)
        let changeEntry = try await addressBook.selectNextEntry(for: .change, fetchBalance: false)
        let changeLockingScript = changeEntry.address.lockingScript.data
        
        let shapedOutputs = await privacyShaper.randomizeOutputs(recipientOutputs)
        
        let selectedUTXOs: [Transaction.Output.Unspent]
        do {
            selectedUTXOs = try await addressBook.selectUTXOs(targetAmount: targetAmount,
                                                              recipientOutputs: shapedOutputs,
                                                              changeLockingScript: changeLockingScript,
                                                              feePerByte: payment.feePerByte,
                                                              strategy: payment.coinSelection)
        } catch {
            throw Error.coinSelectionFailed(error)
        }
        
        let orderedUTXOs = await privacyShaper.applyCoinSelectionHeuristics(to: selectedUTXOs)
        let utxoPrivateKeyPairs = try await addressBook.derivePrivateKeys(for: orderedUTXOs)
        
        var totalInputValue: UInt64 = 0
        for utxo in orderedUTXOs {
            let (updated, didOverflow) = totalInputValue.addingReportingOverflow(utxo.value)
            if didOverflow || updated > Satoshi.maximumSatoshi {
                throw Error.paymentExceedsMaximumAmount
            }
            totalInputValue = updated
        }
        guard totalInputValue >= targetAmount.uint64 else { throw Error.coinSelectionFailed(Address.Book.Error.insufficientFunds) }
        let changePlaceholder = totalInputValue &- targetAmount.uint64
        let changeOutput = Transaction.Output(value: changePlaceholder, lockingScript: changeLockingScript)
        
        let transaction: Transaction
        do {
            transaction = try Transaction.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                recipientOutputs: shapedOutputs,
                                                changeOutput: changeOutput,
                                                feePerByte: payment.feePerByte,
                                                allowDustDonation: payment.allowDustDonation)
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        
        let rawTransactionData = transaction.encode()
        let transactionHash: Transaction.Hash
        do {
            transactionHash = try await outbox.save(transactionData: rawTransactionData)
        } catch {
            throw Error.outboxPersistenceFailed(error)
        }
        
        await addressBook.handleOutgoingTransaction(transaction)
        let producedChangeOutput = transaction.outputs.contains { $0.lockingScript == changeLockingScript }
        if producedChangeOutput {
            try await addressBook.mark(address: changeEntry.address, isUsed: true)
        }
        
        let rawTransactionHex = rawTransactionData.hexadecimalString
        do {
            return try await performRequest(for: .broadcast(transactionHash),
                                            priority: nil,
                                            retryPolicy: retryPolicy) {
                try await broadcastClosure(rawTransactionHex)
                await self.outbox.remove(transactionHash: transactionHash)
                return transactionHash
            }
        } catch {
            throw Error.broadcastFailed(error)
        }
    }
}

extension Account {
    func resubmitPendingTransactions(using session: Network.FulcrumSession,
                                     retryPolicy: RequestRouter<Request>.RetryPolicy = .retry,
                                     broadcaster: (@Sendable (String) async throws -> Void)? = nil) async {
        let broadcastClosure: @Sendable (String) async throws -> Void
        if let broadcaster {
            broadcastClosure = broadcaster
        } else {
            broadcastClosure = { rawTransaction in
                _ = try await session.broadcastTransaction(rawTransaction)
            }
        }
        
        let pending = await outbox.loadPendingTransactions()
        guard !pending.isEmpty else { return }
        
        for (hash, data) in pending {
            let rawTransactionHex = data.hexadecimalString
            await enqueueRequest(for: .broadcast(hash),
                                 priority: nil) {
                try await broadcastClosure(rawTransactionHex)
                await self.outbox.remove(transactionHash: hash)
            }
        }
    }
}
