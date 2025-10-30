import Foundation
import Testing
@testable import OpalBase

@Suite("Account Outbox", .tags(.wallet, .integration))
struct AccountOutboxTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let mnemonicWords = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]
    
    @Test("Outbox persists records and updates statuses")
    func testOutboxPersistenceAndStatusLifecycle() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outbox = try await Account.Outbox(folderURL: temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        
        let statusStream = await outbox.makeStatusStream()
        var statusIterator = statusStream.makeAsyncIterator()
        
        let transactionPayload = Data((0 ..< 180).map { UInt8(truncatingIfNeeded: $0) })
        let transactionHash = try await outbox.save(transactionData: transactionPayload)
        
        let pendingUpdate = await statusIterator.next()
        #expect(pendingUpdate?.transactionHash == transactionHash)
        #expect(pendingUpdate?.status == .pending)
        
        let persistedURLs = try FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
        #expect(persistedURLs.contains { $0.lastPathComponent == transactionHash.naturalOrder.hexadecimalString })
        
        let reloadedOutbox = try await Account.Outbox(folderURL: temporaryDirectory)
        let reloadedEntries = await reloadedOutbox.loadEntries()
        if let reloadedEntry = reloadedEntries[transactionHash] {
            #expect(reloadedEntry.transactionData == transactionPayload)
            #expect(reloadedEntry.status == .pending)
            #expect(reloadedEntry.attemptCount == 0)
        } else {
            #expect(Bool(false), "Expected to reload pending entry from disk")
        }
        
        await outbox.beginBroadcast(for: transactionHash)
        let broadcastingUpdate = await statusIterator.next()
        if case .broadcasting(let attempt)? = broadcastingUpdate?.status {
            #expect(attempt == 1)
        } else {
            #expect(Bool(false), "Expected broadcasting status update")
        }
        let broadcastingEntries = await outbox.loadEntries()
        #expect(broadcastingEntries[transactionHash]?.attemptCount == 1)
        
        let retryDescription = "Network congestion"
        await outbox.recordRetry(for: transactionHash, failureDescription: retryDescription)
        let retryingUpdate = await statusIterator.next()
        if case .retrying(let attempt, let description)? = retryingUpdate?.status {
            #expect(attempt == 2)
            #expect(description == retryDescription)
        } else {
            #expect(Bool(false), "Expected retrying status update")
        }
        
        let failureDescription = "Final rejection"
        await outbox.recordFailure(for: transactionHash, failureDescription: failureDescription)
        let failureUpdate = await statusIterator.next()
        if case .failed(let description)? = failureUpdate?.status {
            #expect(description == failureDescription)
        } else {
            #expect(Bool(false), "Expected failed status update")
        }
        
        await outbox.prepareForEnqueue(transactionHash: transactionHash)
        let requeuedUpdate = await statusIterator.next()
        #expect(requeuedUpdate?.status == .pending)
        let requeuedEntries = await outbox.loadEntries()
        #expect(requeuedEntries[transactionHash]?.attemptCount == 0)
        
        await outbox.remove(transactionHash: transactionHash)
        let completionUpdate = await statusIterator.next()
        #expect(completionUpdate?.status == .completed)
        
        let remaining = await outbox.loadPendingTransactions()
        #expect(remaining.isEmpty)
        
        await outbox.purgeTransactions()
        let purged = try? FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
        #expect(purged?.isEmpty ?? true)
    }
    
    @Test("Outbox tracks live broadcast failures with Fulcrum integration", .timeLimit(.minutes(1)))
    func testOutboxIntegrationTracksFailedBroadcastLifecycle() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        await account.purgeOutbox()
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        await session.ensureTelemetryInstalled(for: account)
        
        let statusStream = await account.makeOutboxStatusStream()
        var statusIterator = statusStream.makeAsyncIterator()
        
        let receivingEntry = try await account.addressBook.selectNextEntry(for: .receiving, fetchBalance: false)
        let previousHash = Transaction.Hash(naturalOrder: Data(repeating: 0x02, count: 32))
        let utxoValue: UInt64 = 250_000
        let unspentOutput = Transaction.Output.Unspent(value: utxoValue,
                                                       lockingScript: receivingEntry.address.lockingScript.data,
                                                       previousTransactionHash: previousHash,
                                                       previousTransactionOutputIndex: 0)
        await account.addressBook.addUTXO(unspentOutput)
        
        let recipientAddress = try Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let amount = try Satoshi(60_000)
        let payment = Account.Payment(recipients: [
            .init(address: recipientAddress, amount: amount)
        ])
        
        do {
            _ = try await account.sendPayment(payment, using: session, retryPolicy: .discard)
            #expect(Bool(false), "Expected broadcast failure")
        } catch let error as Account.Error {
            switch error {
            case .broadcastFailed:
                #expect(true)
            default:
                #expect(Bool(false), "Expected broadcast failure, received \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected Account.Error, received \(error)")
        }
        
        let initialPending = await statusIterator.next()
        #expect(initialPending?.status == .pending)
        let initialFailure = await statusIterator.next()
        if case .failed(let description)? = initialFailure?.status {
            #expect(!description.isEmpty)
        } else {
            #expect(Bool(false), "Expected failed status after initial broadcast")
        }
        
        await account.resubmitPendingTransactions(using: session, retryPolicy: .discard)
        let requeueUpdate = await statusIterator.next()
        #expect(requeueUpdate?.status == .pending)
        
        await account.processQueuedRequests()
        
        let broadcastingUpdate = await statusIterator.next()
        if case .broadcasting(let attempt)? = broadcastingUpdate?.status {
            #expect(attempt == 1)
        } else {
            #expect(Bool(false), "Expected broadcasting status update during resubmission")
        }
        
        let resubmissionFailure = await statusIterator.next()
        if case .failed(let description)? = resubmissionFailure?.status {
            #expect(!description.isEmpty)
        } else {
            #expect(Bool(false), "Expected failed status after resubmission")
        }
        
        let entries = await account.outbox.loadEntries()
        #expect(entries.count == 1)
        #expect(entries.values.first?.attemptCount == 1)
        await account.purgeOutbox()
    }
    
    @Test("save persists transactions and reloads from disk", .timeLimit(.minutes(1)))
    func testSavePersistsTransactionsAndReloadsFromDisk() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        let balance = try await session.fetchAddressBalance(Self.sampleAddress)
        #expect(balance.confirmed >= 0)
        
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outbox = try await Account.Outbox(folderURL: folderURL)
        let statusStream = await outbox.makeStatusStream()
        var iterator = statusStream.makeAsyncIterator()
        
        let transactionData = Data((0..<128).map { UInt8($0) })
        let hash = try await outbox.save(transactionData: transactionData)
        
        let pendingUpdate = await iterator.next()
        #expect(pendingUpdate != nil, "Expected a pending status update after saving")
        if let pendingUpdate {
            #expect(pendingUpdate.transactionHash == hash)
            switch pendingUpdate.status {
            case .pending:
                #expect(true)
            default:
                #expect(Bool(false), "Expected pending status")
            }
        }
        
        let pendingTransactions = await outbox.loadPendingTransactions()
        #expect(pendingTransactions[hash] == transactionData)
        
        let entries = await outbox.loadEntries()
        if let entry = entries[hash] {
            #expect(entry.transactionData == transactionData)
            switch entry.status {
            case .pending:
                #expect(true)
            default:
                #expect(Bool(false), "Expected entry to remain pending")
            }
            #expect(entry.attemptCount == 0)
        } else {
            #expect(Bool(false), "Expected entry to be stored")
        }
        
        let statuses = await outbox.loadStatuses()
        if let status = statuses[hash] {
            switch status {
            case .pending:
                #expect(true)
            default:
                #expect(Bool(false), "Expected pending status in status dictionary")
            }
        } else {
            #expect(Bool(false), "Expected status entry for saved transaction")
        }
        
        let reloadedOutbox = try await Account.Outbox(folderURL: folderURL)
        let reloadedTransactions = await reloadedOutbox.loadPendingTransactions()
        #expect(reloadedTransactions[hash] == transactionData)
        
        await reloadedOutbox.purgeTransactions()
        await outbox.purgeTransactions()
        try? FileManager.default.removeItem(at: folderURL)
    }
    
    @Test("status transitions and cleanup follow broadcast lifecycle", .timeLimit(.minutes(1)))
    func testStatusTransitionsAndCleanupFollowBroadcastLifecycle() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        let balance = try await session.fetchAddressBalance(Self.sampleAddress)
        #expect(balance.confirmed >= 0)
        
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outbox = try await Account.Outbox(folderURL: folderURL)
        let statusStream = await outbox.makeStatusStream()
        var iterator = statusStream.makeAsyncIterator()
        
        let transactionData = Data(repeating: 0xAB, count: 192)
        let hash = try await outbox.save(transactionData: transactionData)
        _ = await iterator.next()
        
        await outbox.beginBroadcast(for: hash)
        let broadcastingUpdate = await iterator.next()
        #expect(broadcastingUpdate != nil, "Expected broadcasting update")
        if let broadcastingUpdate {
            switch broadcastingUpdate.status {
            case .broadcasting(let attempt):
                #expect(attempt == 1)
            default:
                #expect(Bool(false), "Expected broadcasting status")
            }
        }
        
        let entriesAfterBroadcast = await outbox.loadEntries()
        if let entryAfterBroadcast = entriesAfterBroadcast[hash] {
            #expect(entryAfterBroadcast.attemptCount == 1)
        } else {
            #expect(Bool(false), "Expected entry after broadcast")
        }
        
        await outbox.recordRetry(for: hash, failureDescription: "temporary peer failure")
        let retryingUpdate = await iterator.next()
        #expect(retryingUpdate != nil, "Expected retrying update")
        if let retryingUpdate {
            switch retryingUpdate.status {
            case .retrying(let attempt, let failureDescription):
                #expect(attempt == 2)
                #expect(failureDescription == "temporary peer failure")
            default:
                #expect(Bool(false), "Expected retrying status")
            }
        }
        
        await outbox.recordFailure(for: hash, failureDescription: "insufficient fee rate")
        let failureUpdate = await iterator.next()
        #expect(failureUpdate != nil, "Expected failure update")
        if let failureUpdate {
            switch failureUpdate.status {
            case .failed(let failureDescription):
                #expect(failureDescription == "insufficient fee rate")
            default:
                #expect(Bool(false), "Expected failed status")
            }
        }
        
        let entriesAfterFailure = await outbox.loadEntries()
        if let failedEntry = entriesAfterFailure[hash] {
            switch failedEntry.status {
            case .failed(let description):
                #expect(description == "insufficient fee rate")
            default:
                #expect(Bool(false), "Expected failed status in entry")
            }
        } else {
            #expect(Bool(false), "Expected entry after failure")
        }
        
        await outbox.prepareForEnqueue(transactionHash: hash)
        let pendingAfterPrepare = await iterator.next()
        #expect(pendingAfterPrepare != nil, "Expected pending update after prepare")
        if let pendingAfterPrepare {
            switch pendingAfterPrepare.status {
            case .pending:
                #expect(true)
            default:
                #expect(Bool(false), "Expected pending status after prepare")
            }
        }
        
        let entriesAfterPrepare = await outbox.loadEntries()
        if let preparedEntry = entriesAfterPrepare[hash] {
            #expect(preparedEntry.attemptCount == 0)
            switch preparedEntry.status {
            case .pending:
                #expect(true)
            default:
                #expect(Bool(false), "Expected pending status after prepare in entries")
            }
        } else {
            #expect(Bool(false), "Expected prepared entry")
        }
        
        await outbox.remove(transactionHash: hash)
        let completionUpdate = await iterator.next()
        #expect(completionUpdate != nil, "Expected completion update after removal")
        if let completionUpdate {
            switch completionUpdate.status {
            case .completed:
                #expect(true)
            default:
                #expect(Bool(false), "Expected completed status after removal")
            }
        }
        
        let pendingAfterRemoval = await outbox.loadPendingTransactions()
        #expect(pendingAfterRemoval.isEmpty)
        
        await outbox.purgeTransactions()
        let entriesAfterPurge = await outbox.loadEntries()
        #expect(entriesAfterPurge.isEmpty)
        try? FileManager.default.removeItem(at: folderURL)
    }
}
