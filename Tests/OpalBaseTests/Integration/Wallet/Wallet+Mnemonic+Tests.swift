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
}
