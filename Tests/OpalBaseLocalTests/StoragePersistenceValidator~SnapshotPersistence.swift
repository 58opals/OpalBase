// StoragePersistenceValidator~SnapshotPersistence.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("persistState(for:) + restore(accountIdentifiers:) round-trips wallet snapshots and mnemonic state")
    func persistAndRestoreWalletArtifacts() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "session-passphrase")

        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id

        _ = try await account.reserveNextReceivingAddress()
        let expectedSnapshot = await wallet.makeSnapshot()

        let protectionMode = try await storage.persistState(for: wallet)
        #expect([OpalBase.Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try OpalBase.Storage(valueClient: valueClient)
        let session = OpalBase.Storage.PersistenceSession(storage: restoredStorage)
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
    func restoreEmptyStateWhenNothingPersisted() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)
        let session = OpalBase.Storage.PersistenceSession(storage: storage)

        let restored = try await session.restore(accountIdentifiers: .init())

        #expect(restored.walletSnapshot == nil)
        #expect(restored.accountSnapshots.isEmpty)
        #expect(restored.addressBookSnapshots.isEmpty)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }

    @Test("save(snapshot:accountIdentifiers:) rejects missing account identifiers")
    func rejectMissingAccountIdentifiersWhenSavingSnapshot() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)
        let session = OpalBase.Storage.PersistenceSession(storage: storage)

        let wallet = try await AccountTestFixtures.makeWallet()

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
            Issue.record("Expected OpalBase.Storage.Error.missingAccountIdentifier(\(missingIndex)) but save completed.")
        } catch OpalBase.Storage.Error.missingAccountIdentifier(let index) {
            #expect(index == missingIndex)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
