import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Fulcrum Creation", .tags(.integration, .network, .fulcrum))
struct WalletFulcrumCreationSuite {
    @Test("generates receiving address from mnemonic", .tags(.integration, .network, .fulcrum))
    func generatesReceivingAddressFromMnemonic() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(length: .short)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        let receivingEntry = try await account.addressBook.selectNextEntry(for: .receiving)
        
        let rootExtendedKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let derivationPath = try await DerivationPath(purpose: wallet.derivationPath.purpose,
                                                      coinType: wallet.derivationPath.coinType,
                                                      account: .init(rawIndexInteger: 0),
                                                      usage: .receiving,
                                                      index: 0)
        let derivedPublicKey = try rootExtendedKey.deriveChildPublicKey(at: derivationPath)
        let publicKey = try PublicKey(compressedData: derivedPublicKey.publicKey)
        let expectedAddress = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        
        #expect(receivingEntry.address.string == expectedAddress.string)
    }
    
    @Test("restores wallet from snapshot", .tags(.integration, .network, .fulcrum))
    func restoresWalletFromSnapshot() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(length: .short)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let snapshot = await wallet.makeSnapshot()
        let restored = try await Wallet(from: snapshot)
        
        let walletAccountCount = await wallet.numberOfAccounts
        let restoredAccountCount = await restored.numberOfAccounts
        #expect(walletAccountCount == restoredAccountCount)
        
        let account = try await wallet.fetchAccount(at: 0)
        let restoredAccount = try await restored.fetchAccount(at: 0)
        
        let receivingEntry = try await account.addressBook.selectNextEntry(for: .receiving)
        let restoredEntry = try await restoredAccount.addressBook.selectNextEntry(for: .receiving)
        
        let accountID = await account.id
        let restoredAccountID = await restoredAccount.id
        
        #expect(receivingEntry.address.string == restoredEntry.address.string)
        #expect(accountID == restoredAccountID)
    }
}
