// WalletValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Wallet", .tags(.unit, .wallet))
struct WalletValidator {
    @Test("fetchAccount locates accounts regardless of insertion order")
    func fetchAccountLocatesOutOfOrderAccountIndices() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
        
        try await wallet.addAccount(unhardenedIndex: 3)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let thirdAccount = try await wallet.fetchAccount(at: 3)
        let zerothAccount = try await wallet.fetchAccount(at: 0)
        
        #expect(await thirdAccount.unhardenedIndex == 3)
        #expect(await zerothAccount.unhardenedIndex == 0)
    }
    
    @Test("fetchAccount throws when the index is missing")
    func fetchAccountRejectsMissingAccount() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
        
        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: 0)) {
            _ = try await wallet.fetchAccount(at: 0)
        }
    }
    
    @Test("fetchAccount rejects unknown account indices")
    func fetchAccountRejectsUnknownAccountIndices() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
        
        let missingIndex: UInt32 = 7
        
        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: missingIndex)) {
            _ = try await wallet.fetchAccount(at: missingIndex)
        }
    }
}
