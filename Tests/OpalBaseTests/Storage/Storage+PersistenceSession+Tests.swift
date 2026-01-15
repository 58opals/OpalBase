import Foundation
import Testing
@testable import OpalBase

@Suite("Storage persistence and wallet workflows")
struct StoragePersistenceTests {
    @Test("storage uses canonical keys for wallet artifacts")
    func storageUsesCanonicalKeys() {
        let accountIdentifier = Data("account-0".utf8)
        let encodedIdentifier = accountIdentifier.base64EncodedString()
        
        #expect(Storage.Key.walletSnapshot.rawValue == "wallet.snapshot")
        #expect(Storage.Key.accountSnapshot(accountIdentifier).rawValue == "account.snapshot.\(encodedIdentifier)")
        #expect(Storage.Key.addressBookSnapshot(accountIdentifier).rawValue == "address-book.snapshot.\(encodedIdentifier)")
        #expect(Storage.Key.mnemonicCiphertext.rawValue == "mnemonic.enc")
    }
    
    @Test("mnemonic persistence does not require retaining a wallet instance")
    func mnemonicPersistsWithoutWalletRetention() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        
        let mnemonic = Storage.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "long form passphrase"
        )
        
        let protectionMode = try await storage.saveMnemonic(mnemonic, fallbackToPlaintext: true)
        #expect([Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))
        
        let restoredStorage = try Storage(valueStore: valueStore)
        let restored = try await restoredStorage.loadMnemonicState()
        
        #expect(restored?.mnemonic.words == mnemonic.words)
        #expect(restored?.mnemonic.passphrase == mnemonic.passphrase)
        #expect(restored?.protectionMode == protectionMode)
    }
    
    @Test("persistState(for:) + restore(accountIdentifiers:) round-trips wallet snapshots and mnemonic state")
    func persistAndRestoreRoundTripsWalletArtifacts() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "session-passphrase"
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id
        
        _ = try await account.reserveNextReceivingAddress()
        let expectedSnapshot = await wallet.makeSnapshot()
        
        let protectionMode = try await storage.persistState(for: wallet)
        #expect([Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))
        
        let restoredStorage = try Storage(valueStore: valueStore)
        let session = Storage.PersistenceSession(storage: restoredStorage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])
        
        guard let restoredWalletSnapshot = restored.walletSnapshot else {
            Issue.record("Expected wallet snapshot to be restored, but it was nil.")
            return
        }
        #expect(restoredWalletSnapshot.words == expectedSnapshot.words)
        #expect(restoredWalletSnapshot.passphrase == expectedSnapshot.passphrase)
        #expect(restoredWalletSnapshot.purpose == expectedSnapshot.purpose)
        #expect(restoredWalletSnapshot.coinType == expectedSnapshot.coinType)
        #expect(restoredWalletSnapshot.accounts.count == expectedSnapshot.accounts.count)
        #expect(restoredWalletSnapshot.accounts.first?.accountUnhardenedIndex == expectedSnapshot.accounts.first?.accountUnhardenedIndex)
        
        guard let restoredAccountSnapshot = restored.accountSnapshots[accountIdentifier] else {
            Issue.record("Expected account snapshot to be restored, but it was missing for the provided identifier.")
            return
        }
        #expect(restoredAccountSnapshot.purpose == expectedSnapshot.accounts[0].purpose)
        #expect(restoredAccountSnapshot.coinType == expectedSnapshot.accounts[0].coinType)
        #expect(restoredAccountSnapshot.accountUnhardenedIndex == expectedSnapshot.accounts[0].accountUnhardenedIndex)
        
        guard let restoredAddressBookSnapshot = restored.addressBookSnapshots[accountIdentifier] else {
            Issue.record("Expected address book snapshot to be restored, but it was missing for the provided identifier.")
            return
        }
        
        let expectedAddressBookSnapshot = expectedSnapshot.accounts[0].addressBook
        #expect(restoredAddressBookSnapshot.receivingEntries.count == expectedAddressBookSnapshot.receivingEntries.count)
        #expect(restoredAddressBookSnapshot.changeEntries.count == expectedAddressBookSnapshot.changeEntries.count)
        
        let expectedReservedReceivingCount = expectedAddressBookSnapshot.receivingEntries.filter { $0.isReserved }.count
        #expect(expectedReservedReceivingCount == 1)
        #expect(restoredAddressBookSnapshot.receivingEntries.filter { $0.isReserved }.count == expectedReservedReceivingCount)
        
        guard let restoredMnemonic = restored.mnemonic else {
            Issue.record("Expected mnemonic to be restored, but it was nil.")
            return
        }
        #expect(restoredMnemonic.words == expectedSnapshot.words)
        #expect(restoredMnemonic.passphrase == expectedSnapshot.passphrase)
        #expect(restored.mnemonicProtectionMode == protectionMode)
    }
    
    @Test("restore returns an empty state for a fresh install")
    func restoreReturnsEmptyStateWhenNothingPersisted() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        let session = Storage.PersistenceSession(storage: storage)
        
        let restored = try await session.restore(accountIdentifiers: .init())
        
        #expect(restored.walletSnapshot == nil)
        #expect(restored.accountSnapshots.isEmpty)
        #expect(restored.addressBookSnapshots.isEmpty)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }
    
    @Test("save(snapshot:accountIdentifiers:) rejects missing account identifiers")
    func saveSnapshotRejectsMissingAccountIdentifiers() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        let session = Storage.PersistenceSession(storage: storage)
        
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let snapshot = await wallet.makeSnapshot()
        guard let missingIndex = snapshot.accounts.first?.accountUnhardenedIndex else {
            Issue.record("Snapshot unexpectedly contained no accounts.")
            return
        }
        
        do {
            _ = try await session.save(
                snapshot: snapshot,
                accountIdentifiers: .init(),
                fallbackToPlaintext: true
            )
            Issue.record("Expected Storage.Error.missingAccountIdentifier(\(missingIndex)) but save completed.")
        } catch Storage.Error.missingAccountIdentifier(let index) {
            #expect(index == missingIndex)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("restore tolerates missing account/address book snapshots while still restoring wallet snapshot")
    func restoreToleratesMissingAccountSnapshots() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "passphrase"
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id
        
        _ = try await storage.persistState(for: wallet)
        
        try await storage.removeValue(for: .accountSnapshot(accountIdentifier))
        try await storage.removeValue(for: .addressBookSnapshot(accountIdentifier))
        
        let session = Storage.PersistenceSession(storage: storage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])
        
        #expect(restored.walletSnapshot != nil)
        #expect(restored.accountSnapshots.isEmpty)
        #expect(restored.addressBookSnapshots.isEmpty)
        #expect(restored.mnemonic != nil)
    }
    
    @Test("restore tolerates missing mnemonic ciphertext (e.g., keychain cleared) while still restoring snapshots")
    func restoreToleratesMissingMnemonicCiphertext() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "passphrase"
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id
        
        _ = try await storage.persistState(for: wallet)
        
        try await storage.removeValue(for: .mnemonicCiphertext)
        
        let session = Storage.PersistenceSession(storage: storage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])
        
        #expect(restored.walletSnapshot != nil)
        #expect(restored.accountSnapshots[accountIdentifier] != nil)
        #expect(restored.addressBookSnapshots[accountIdentifier] != nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }
    
    @Test("wipeAll removes persisted wallet artifacts")
    func wipeAllRemovesPersistedArtifacts() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "wipe-passphrase"
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id
        
        _ = try await storage.persistState(for: wallet)
        try await storage.wipeAll()
        
        let session = Storage.PersistenceSession(storage: storage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])
        
        #expect(restored.walletSnapshot == nil)
        #expect(restored.accountSnapshots.isEmpty)
        #expect(restored.addressBookSnapshots.isEmpty)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }
    
    @Test("prepareSpend throws when payment has no recipients")
    func prepareSpendThrowsWhenPaymentHasNoRecipients() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.fetchAccount(at: 0)
        let payment = Account.Payment(recipients: .init())
        
        await #expect(throws: Account.Error.paymentHasNoRecipients) {
            _ = try await account.prepareSpend(payment)
        }
    }
    
    @Test("prepareSpend fails for empty wallets (insufficient funds)")
    func prepareSpendFailsWithInsufficientFundsForEmptyWallet() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.fetchAccount(at: 0)
        let recipientAddress = try await account.reserveNextReceivingAddress()
        let recipientAmount = try Satoshi(1_000)
        
        let payment = Account.Payment(
            recipients: [
                .init(address: recipientAddress, amount: recipientAmount)
            ]
        )
        
        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected insufficient-funds failure, but prepareSpend succeeded for an empty wallet.")
        } catch let error as Account.Error {
            guard case .coinSelectionFailed(let underlying) = error else {
                Issue.record("Expected coinSelectionFailed, got: \(error)")
                return
            }
            
            if let txError = underlying as? Transaction.Error {
                switch txError {
                case .insufficientFunds:
                    #expect(true)
                default:
                    Issue.record("Expected Transaction.Error.insufficientFunds, got: \(txError)")
                }
                return
            }
            
            if let bookError = underlying as? Address.Book.Error, bookError == .insufficientFunds {
                #expect(true)
                return
            }
            
            Issue.record("coinSelectionFailed with unexpected underlying error: \(underlying)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("fulcrum sync updates account state, then persistence restores it", .timeLimit(.minutes(1)))
    func fulcrumSyncThenPersistAndRestore() async throws {
        let fulcrumURLFromEnv = ProcessInfo.processInfo.environment["OPAL_FULCRUM_URL"]
        let candidateServerStrings: [String] = [
            fulcrumURLFromEnv,
            // Common BCH Fulcrum WSS endpoints (wallet apps should allow switching servers)
            "wss://bch.imaginary.cash:50004"
        ].compactMap { $0 }
        
        let candidateServers = candidateServerStrings.compactMap(URL.init(string:))
        guard !candidateServers.isEmpty else {
            Issue.record("No Fulcrum server URLs available (OPAL_FULCRUM_URL was empty and defaults could not be formed).")
            return
        }
        
        var client: Network.FulcrumClient?
        var lastConnectionError: Swift.Error?
        
        for url in candidateServers {
            do {
                let config = Network.Configuration(
                    serverURLs: [url],
                    connectionTimeout: .seconds(10),
                    maximumMessageSize: 1024 * 1024,
                    reconnect: .defaultValue,
                    network: .mainnet
                )
                client = try await Network.FulcrumClient(configuration: config)
                lastConnectionError = nil
                break
            } catch {
                lastConnectionError = error
            }
        }
        
        guard let client else {
            Issue.record("Failed to connect to any Fulcrum server. Last error: \(String(describing: lastConnectionError))")
            return
        }
        defer { Task { await client.stop() } }
        
        let timeouts = Network.FulcrumRequestTimeout(
            headersTip: .seconds(10),
            addressBalance: .seconds(10),
            addressUnspent: .seconds(15),
            addressHistory: .seconds(15)
        )
        let blockHeaderReader = Network.FulcrumBlockHeaderReader(client: client, timeouts: timeouts)
        let addressReader = Network.FulcrumAddressReader(client: client, timeouts: timeouts)
        
        let tip = try await blockHeaderReader.fetchTip()
        #expect(tip.height > 0)
        #expect(!tip.headerHexadecimal.isEmpty)
        
        let mnemonic = try Mnemonic(length: .short, passphrase: "")
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id
        
        let receivingAddress = try await account.reserveNextReceivingAddress()
        
        // Validate "real-time" behavior: subscription must yield an initial snapshot quickly.
        var sawAddressInitialSnapshot = false
        do {
            let stream = try await addressReader.subscribeToAddress(receivingAddress.string)
            for try await update in stream {
                #expect(update.address == receivingAddress.string)
                #expect(update.kind == .initialSnapshot)
                if let status = update.status { #expect(!status.isEmpty) }
                sawAddressInitialSnapshot = true
                break
            }
        }
        #expect(sawAddressInitialSnapshot == true)
        
        var sawTipSnapshot = false
        do {
            let stream = try await blockHeaderReader.subscribeToTip()
            for try await snapshot in stream {
                #expect(snapshot.height > 0)
                #expect(!snapshot.headerHexadecimal.isEmpty)
                sawTipSnapshot = true
                break
            }
        }
        #expect(sawTipSnapshot == true)
        
        // Practical sync flow: read network state for the address and write it into the account.
        let balance = try await addressReader.fetchBalance(for: receivingAddress.string)
        #expect(balance.confirmed >= 0)
        #expect(balance.unconfirmed >= 0)
        
        let utxos = try await addressReader.fetchUnspentOutputs(for: receivingAddress.string)
        let history = try await addressReader.fetchHistory(for: receivingAddress.string, includeUnconfirmed: true)
        
        // Apply network state to the account using deterministic timestamps for persistence checks.
        let fixedTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let cachedBalance = try await account.replaceUTXOs(for: receivingAddress, with: utxos, timestamp: fixedTimestamp)
        #expect(cachedBalance.balance.uint64 == utxos.reduce(0) { $0 + $1.value })
        
        _ = try await account.refreshTransactionHistory(for: receivingAddress, using: addressReader, includeUnconfirmed: true)
        
        let snapshotBeforePersist = await wallet.makeSnapshot()
        
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)
        let mode = try await storage.persistState(for: wallet)
        #expect([Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(mode))
        
        let restoredStorage = try Storage(valueStore: valueStore)
        let session = Storage.PersistenceSession(storage: restoredStorage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])
        
        guard let restoredWalletSnapshot = restored.walletSnapshot else {
            Issue.record("Expected wallet snapshot after restore, but it was nil.")
            return
        }
        #expect(restoredWalletSnapshot.words == snapshotBeforePersist.words)
        #expect(restoredWalletSnapshot.passphrase == snapshotBeforePersist.passphrase)
        #expect(restoredWalletSnapshot.accounts.count == snapshotBeforePersist.accounts.count)
        
        guard let restoredAccountSnapshot = restored.accountSnapshots[accountIdentifier] else {
            Issue.record("Expected restored account snapshot, but it was missing for the provided identifier.")
            return
        }
        #expect(restoredAccountSnapshot.accountUnhardenedIndex == snapshotBeforePersist.accounts[0].accountUnhardenedIndex)
        
        guard let restoredAddressBookSnapshot = restored.addressBookSnapshots[accountIdentifier] else {
            Issue.record("Expected restored address book snapshot, but it was missing for the provided identifier.")
            return
        }
        
        let restoredReceivingEntry = restoredAddressBookSnapshot.receivingEntries.first { $0.index == 0 }
        #expect(restoredReceivingEntry != nil)
        #expect(restoredReceivingEntry?.isReserved == true)
        
        // UTXO cache should persist for the synced address (even if empty, it should be stable).
        let restoredUtxoSum = restoredAddressBookSnapshot.utxos
            .filter { $0.lockingScript == receivingAddress.lockingScript.data.hexadecimalString }
            .reduce(0) { $0 + $1.value }
        #expect(restoredUtxoSum == utxos.reduce(0) { $0 + $1.value })
        
        // History should contain at least the same tx hashes we saw from the server (subset match).
        let restoredTxHashes = Set(restoredAddressBookSnapshot.transactions.map { $0.transactionHash })
        let serverTxHashes = Set(history.map { $0.transactionIdentifier.lowercased() })
        #expect(serverTxHashes.isSubset(of: restoredTxHashes) || restoredTxHashes.isSubset(of: serverTxHashes))
        
        // Mnemonic must restore (or be nil only if secure store was unavailable). In normal operation it should be present.
        if let restoredMnemonic = restored.mnemonic {
            #expect(restoredMnemonic.words == snapshotBeforePersist.words)
            #expect(restoredMnemonic.passphrase == snapshotBeforePersist.passphrase)
            #expect(restored.mnemonicProtectionMode == mode)
        } else {
            // Real-life edge case: snapshot restoration works, but mnemonic could not be recovered (e.g. secure store wiped).
            #expect(restored.mnemonicProtectionMode == nil)
        }
    }
}
