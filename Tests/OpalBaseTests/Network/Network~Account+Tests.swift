import Foundation
import Testing
@testable import OpalBase

@Suite("Network.FulcrumSession Account", .tags(.network, .integration, .wallet))
struct NetworkFulcrumSessionAccountTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let mnemonicWords = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]
    
    @Test("resumeQueuedWork installs telemetry and resumes suspended queue", .timeLimit(.minutes(1)))
    func testResumeQueuedWorkInstallsTelemetry() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        await account.suspendQueuedRequests()
        await account.enqueueRequest(for: .calculateBalance, priority: nil) {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        let telemetryStream = await session.makeTelemetryStream()
        let accountIdentifier = await account.id
        var iterator = telemetryStream.makeAsyncIterator()
        
        await session.resumeQueuedWork(for: account)
        
        var recordedDepths: [Int] = .init()
        while recordedDepths.count < 2 {
            guard let event = await iterator.next() else { break }
            switch event {
            case .queueDepthDidChange(let context, let depth) where context.accountIdentifier == accountIdentifier:
                recordedDepths.append(depth)
                if depth == 0 { break }
            default:
                continue
            }
        }
        
        #expect(recordedDepths.contains(1))
        #expect(recordedDepths.contains(0))
    }
    
    @Test("computeCachedBalance aggregates cached entries", .timeLimit(.minutes(1)))
    func testComputeCachedBalanceAggregatesEntries() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        let account = try await session.createAccount(for: wallet, at: 0)
        let addressBook = await account.addressBook
        
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let changeEntries = await addressBook.listEntries(for: .change)
        let receivingBalance = try Satoshi(12_500)
        let changeBalance = try Satoshi(3_750)
        
        if let firstReceiving = receivingEntries.first {
            try await addressBook.updateCache(for: firstReceiving.address, with: receivingBalance)
        }
        if let firstChange = changeEntries.first {
            try await addressBook.updateCache(for: firstChange.address, with: changeBalance)
        }
        
        let cachedBalance = try await session.computeCachedBalance(for: account)
        
        #expect(cachedBalance.uint64 == receivingBalance.uint64 + changeBalance.uint64)
    }
    
    @Test("computeBalance refreshes stale caches using the network", .timeLimit(.minutes(1)))
    func testComputeBalanceRefreshesStaleCaches() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        let account = try await session.createAccount(for: wallet, at: 0)
        let addressBook = await account.addressBook
        
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let changeEntries = await addressBook.listEntries(for: .change)
        let zeroBalance = Satoshi()
        let preparedChangeBalance = try Satoshi(5_000)
        let firstChangeAddress = changeEntries.first?.address
        
        if let firstChange = changeEntries.first {
            try await addressBook.updateCache(for: firstChange.address, with: preparedChangeBalance)
        }
        for entry in changeEntries.dropFirst() {
            try await addressBook.updateCache(for: entry.address, with: zeroBalance)
        }
        for entry in receivingEntries.dropFirst() {
            try await addressBook.updateCache(for: entry.address, with: zeroBalance)
        }
        
        let refreshedBalance = try await session.computeBalance(for: account)
        let cachedBalance = try await session.computeCachedBalance(for: account)
        
        #expect(refreshedBalance.uint64 == cachedBalance.uint64)
        
        if let firstReceiving = receivingEntries.first {
            let cachedReceivingBalance = try await addressBook.readCachedBalance(for: firstReceiving.address)
            #expect(cachedReceivingBalance != nil)
            if let firstChangeAddress {
                let changeContribution = try await addressBook.readCachedBalance(for: firstChangeAddress)?.uint64 ?? 0
                #expect((cachedReceivingBalance?.uint64 ?? 0) + changeContribution == refreshedBalance.uint64)
            } else {
                #expect((cachedReceivingBalance?.uint64 ?? 0) == refreshedBalance.uint64)
            }
        }
    }
    
    @Test("refreshCachedBalance aggregates cached balances without refreshing")
    func testRefreshBalancesUsesCachedValues() async throws {
        let session = try await Network.FulcrumSession()
        await session.updateState(.running)
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let addressBook = await account.addressBook
        
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let changeEntries = await addressBook.listEntries(for: .change)
        
        let receivingBalance = try Satoshi(1_000)
        let changeBalance = try Satoshi(2_500)
        
        if let firstReceiving = receivingEntries.first {
            try await addressBook.updateCache(for: firstReceiving.address, with: receivingBalance)
        }
        for entry in receivingEntries.dropFirst() {
            try await addressBook.updateCache(for: entry.address, with: Satoshi())
        }
        for (index, entry) in changeEntries.enumerated() {
            let balance = index == 0 ? changeBalance : Satoshi()
            try await addressBook.updateCache(for: entry.address, with: balance)
        }
        
        let total = try await session.refreshCachedBalance(for: account, options: .init())
        #expect(total.uint64 == receivingBalance.uint64 + changeBalance.uint64)
    }
    
    @Test("fetchDetailedTransactions returns records for scoped addresses")
    func testFetchDetailedTransactionsFiltersByScope() async throws {
        let session = try await Network.FulcrumSession()
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let addressBook = await account.addressBook
        
        guard let receivingEntry = await addressBook.listEntries(for: .receiving).first,
              let changeEntry = await addressBook.listEntries(for: .change).first else {
            Issue.record("Expected address entries for both usages")
            return
        }
        
        let receivingScriptHash = receivingEntry.address.makeScriptHash().hexadecimalString
        let changeScriptHash = changeEntry.address.makeScriptHash().hexadecimalString
        let timestamp = Date()
        
        let receivingHash = Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let changeHash = Transaction.Hash(naturalOrder: Data(repeating: 0x02, count: 32))
        
        let receivingHistoryEntry = Address.Book.History.Transaction.Entry(transactionHash: receivingHash,
                                                                           height: 120,
                                                                           fee: 150)
        let changeHistoryEntry = Address.Book.History.Transaction.Entry(transactionHash: changeHash,
                                                                        height: 95,
                                                                        fee: 200)
        
        _ = await addressBook.updateTransactionHistory(for: receivingScriptHash,
                                                       entries: [receivingHistoryEntry],
                                                       timestamp: timestamp)
        _ = await addressBook.updateTransactionHistory(for: changeScriptHash,
                                                       entries: [changeHistoryEntry],
                                                       timestamp: timestamp)
        
        let records = try await session.fetchDetailedTransactions(for: account, scope: .receiving)
        
        #expect(records.count == 1)
        #expect(records.first?.transactionHash == receivingHash)
        #expect(records.first?.scriptHashes.contains(receivingScriptHash) == true)
    }
    
    @Test("refreshAddressUsageStatus reports newly used addresses")
    func testRefreshAddressUsageStatusDetectsNewUsage() async throws {
        let session = try await Network.FulcrumSession()
        await session.updateState(.running)
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let addressBook = await account.addressBook
        
        guard let targetEntry = await addressBook.listEntries(for: .receiving).first else {
            Issue.record("Expected at least one receiving entry")
            return
        }
        
        try await addressBook.mark(address: targetEntry.address, isUsed: false)
        
        let newlyUsed = try await session.refreshAddressUsageStatus(for: account,
                                                                    scope: .receiving,
                                                                    options: .init(),
                                                                    shouldScanGap: false) { _, entry, addressBook in
            if entry.address == targetEntry.address {
                try await addressBook.mark(address: entry.address, isUsed: true)
            }
        }
        
        #expect(newlyUsed == [targetEntry.address])
    }
}
