// SnapshotPersistencePort_.swift

import Foundation

public protocol SnapshotPersistencePort: Sendable {
    func saveWalletSnapshot(_ snapshot: Wallet.Snapshot) async throws
    func loadWalletSnapshot() async throws -> Wallet.Snapshot?
    func saveAccountSnapshot(_ snapshot: Account.Snapshot, accountIdentifier: Data) async throws
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> Account.Snapshot?
    func saveAddressBookSnapshot(_ snapshot: Address.Book.Snapshot, accountIdentifier: Data) async throws
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> Address.Book.Snapshot?
    func wipeAll() async throws
}
