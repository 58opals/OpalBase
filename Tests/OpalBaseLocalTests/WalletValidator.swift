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

    @Test("fetchAccount rejects missing account indices", arguments: [UInt32(0), 7])
    func rejectMissingAccount(_ missingIndex: UInt32) async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())

        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: missingIndex)) {
            _ = try await wallet.fetchAccount(at: missingIndex)
        }
    }

    @Test("addAccount rejects duplicate unhardened indices")
    func addAccountRejectsDuplicateIndices() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())

        try await wallet.addAccount(unhardenedIndex: 0)

        await #expect(throws: OpalBase.Wallet.Error.accountAlreadyExists(index: 0)) {
            try await wallet.addAccount(unhardenedIndex: 0)
        }
    }
}
