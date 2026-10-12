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

    @Test("concurrent addAccount calls preserve the first account and reject the duplicate")
    func concurrentAddAccountRejectsDuplicateIndices() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
        let start = ConcurrentAccountCreationStart()

        let createdAccounts = try await withThrowingTaskGroup(of: OpalBase.Account?.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    await start.arrive()
                    do {
                        try await wallet.addAccount(unhardenedIndex: 0)
                        return try await wallet.fetchAccount(at: 0)
                    } catch let error as OpalBase.Wallet.Error {
                        guard error == .accountAlreadyExists(index: 0) else { throw error }
                        return nil
                    }
                }
            }

            var createdAccounts: [OpalBase.Account] = []
            for try await account in group {
                if let account { createdAccounts.append(account) }
            }
            return createdAccounts
        }

        try #require(createdAccounts.count == 1)
        #expect(await wallet.numberOfAccounts == 1)
        #expect(try await wallet.fetchAccount(at: 0) === createdAccounts[0])
    }
}

private actor ConcurrentAccountCreationStart {
    private var firstArrival: CheckedContinuation<Void, Never>?

    func arrive() async {
        if let firstArrival {
            self.firstArrival = nil
            firstArrival.resume()
        } else {
            await withCheckedContinuation { firstArrival = $0 }
        }
    }
}
