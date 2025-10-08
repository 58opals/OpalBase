import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Mnemonic Integration", .tags(.integration, .network, .fulcrum))
struct WalletMnemonicIntegrationSuite {
    private static let mnemonicWords: [String] = [
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "about"
    ]
    
    private static let expectedReceivingAddress = "bitcoincash:qqyx49mu0kkn9ftfj6hje6g2wfer34yfnq5tahq3q6"
    private static let balanceVerificationSampleSize = 5
    
    @Test("derives the receiving address from the mnemonic using Fulcrum")
    func derivesReceivingAddressFromMnemonic() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        let entry = try await account.addressBook.selectNextEntry(for: .receiving)
        
        #expect(entry.address.string == Self.expectedReceivingAddress)
    }
    
    @Test("restores mnemonic wallets and syncs with Fulcrum", .tags(.integration, .network, .fulcrum))
    func restoresMnemonicWalletsAndSyncsWithFulcrum() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonicWords = Self.mnemonicWords
        let mnemonic = try Mnemonic(words: mnemonicWords)
        let walletA = Wallet(mnemonic: mnemonic)
        let walletB = Wallet(mnemonic: try Mnemonic(words: mnemonicWords))
        
        try await walletA.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        try await walletB.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let accountA = try await walletA.fetchAccount(at: 0)
        let accountB = try await walletB.fetchAccount(at: 0)
        
        let receivingEntryA = try await accountA.addressBook.selectNextEntry(for: .receiving)
        let receivingEntryB = try await accountB.addressBook.selectNextEntry(for: .receiving)
        let changeEntryA = try await accountA.addressBook.selectNextEntry(for: .change)
        let changeEntryB = try await accountB.addressBook.selectNextEntry(for: .change)
        
        let accountIDA = await accountA.id
        let accountIDB = await accountB.id
        
        #expect(accountIDA == accountIDB)
        #expect(receivingEntryA.address.string == receivingEntryB.address.string)
        #expect(changeEntryA.address.string == changeEntryB.address.string)
        
        _ = try await walletA.calculateBalance()
        _ = try await walletB.calculateBalance()
    }
    
    @Test("restores wallet snapshot without changing derivations", .tags(.integration, .network, .fulcrum))
    func restoresWalletSnapshotWithoutChangingDerivations() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        let addressBook = await account.addressBook
        
        let originalReceivingAddresses = await addressBook
            .listEntries(for: .receiving)
            .map { $0.address.string }
        let originalChangeAddresses = await addressBook
            .listEntries(for: .change)
            .map { $0.address.string }
        
        let snapshot = await wallet.makeSnapshot()
        let restored = try await Wallet(from: snapshot)
        let restoredAccount = try await restored.fetchAccount(at: 0)
        let restoredAddressBook = await restoredAccount.addressBook
        
        let restoredReceivingAddresses = await restoredAddressBook
            .listEntries(for: .receiving)
            .map { $0.address.string }
        let restoredChangeAddresses = await restoredAddressBook
            .listEntries(for: .change)
            .map { $0.address.string }
        
        let hasSameNumberOfAccounts = await restored.numberOfAccounts == wallet.numberOfAccounts
        
        #expect(hasSameNumberOfAccounts)
        #expect(restoredReceivingAddresses == originalReceivingAddresses)
        #expect(restoredChangeAddresses == originalChangeAddresses)
    }
    
    @Test("reports consistent balances between aggregate and sampled entries", .tags(.integration, .network, .fulcrum))
    func reportsConsistentBalancesBetweenAggregateAndSampledEntries() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        
        let aggregateBalance = try await account.calculateBalance()
        
        let connectionPool = await account.fulcrumPool
        let node = try await connectionPool.acquireNode()
        let addressBook = await account.addressBook
        
        let receivingSampleSize = 5
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let sampledEntries = receivingEntries.prefix(receivingSampleSize)
        
        var sampledTotal: UInt64 = 0
        for entry in sampledEntries {
            let balance = try await addressBook.fetchBalance(for: entry.address, using: node)
            sampledTotal &+= balance.uint64
        }
        
        let aggregateValue = aggregateBalance.uint64
        let delta = aggregateValue > sampledTotal ? aggregateValue - sampledTotal : sampledTotal - aggregateValue
        
        #expect(delta <= 1, "Aggregate balance diverges from sampled entry balances by more than a satoshi.")
    }
    
    @Test("verifies aggregate balance consistency with Fulcrum", .tags(.integration, .network, .fulcrum))
    func verifiesAggregateBalanceConsistencyWithFulcrum() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let (_, account) = try await Self.makeSeededWalletAndAccount(endpoint: endpoint)
        
        let aggregateBalance = try await account.calculateBalance()
        let node = try await account.fulcrumPool.acquireNode()
        let addressBook = await account.addressBook
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let sampledEntries = receivingEntries.prefix(Self.balanceVerificationSampleSize)
        
        var summedBalance = Satoshi()
        for entry in sampledEntries {
            let entryBalance = try await addressBook.fetchBalance(for: entry.address, using: node)
            summedBalance = try summedBalance + entryBalance
        }
        
        let aggregateValue = aggregateBalance.uint64
        let sampledValue = summedBalance.uint64
        let difference = aggregateValue > sampledValue ? aggregateValue - sampledValue : sampledValue - aggregateValue
        
        #expect(difference <= 1,
                "Aggregate balance \(aggregateValue) and sampled balance \(sampledValue) differ by more than one satoshi")
    }
    
    private static func makeSeededWalletAndAccount(endpoint: String) async throws -> (Wallet, Account) {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        return (wallet, account)
    }
    
    @Test("matches Fulcrum balance with refreshed UTXO set", .tags(.integration, .network, .fulcrum))
    func matchesFulcrumBalanceWithRefreshedUTXOSet() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        let accountIndex = UInt32(clamping: Environment.getTestBalanceAccountIndex())
        
        for index in UInt32(0)...accountIndex {
            try await wallet.addAccount(unhardenedIndex: index, fulcrumServerURLs: [endpoint])
        }
        
        let account = try await wallet.fetchAccount(at: accountIndex)
        
        try await account.refreshUTXOSet()
        
        let utxos = await account.addressBook.listUTXOs()
        let summedValue = utxos.reduce(into: UInt64(0)) { partial, utxo in
            partial &+= utxo.value
        }
        let summed = try Satoshi(summedValue)
        
        let calculated = try await account.calculateBalance()
        
        #expect(calculated == summed)
        
        if let firstReceiving = await account.addressBook.listEntries(for: .receiving).first?.address {
            let node = try await account.fulcrumPool.acquireNode()
            let perAddressValue = utxos.reduce(into: UInt64(0)) { partial, utxo in
                if utxo.lockingScript == firstReceiving.lockingScript.data {
                    partial &+= utxo.value
                }
            }
            let perAddressBalance = try Satoshi(perAddressValue)
            let remoteBalance = try await node.balance(for: firstReceiving, includeUnconfirmed: true)
            
            #expect(perAddressBalance == remoteBalance)
        }
    }
}
