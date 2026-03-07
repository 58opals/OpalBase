// SnapshotPersistenceAdapter_.swift

import Foundation

public protocol SnapshotPersistenceAdapter: Sendable {
    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws
    func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot?
    func saveAccountSnapshot(_ snapshot: OpalBase.Account.SnapshotModel, accountIdentifier: Data) async throws
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.SnapshotModel?
    func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.SnapshotModel, accountIdentifier: Data) async throws
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.SnapshotModel?
    func wipeAll() async throws
}

