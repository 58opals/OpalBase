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
}
