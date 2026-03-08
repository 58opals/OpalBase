// OpalBase+Storage+SnapshotStore_.swift

import Foundation

extension _OpalBase.Storage {
    public protocol SnapshotStore: Sendable {
        func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws
        func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot?
        func saveAccountSnapshot(_ snapshot: OpalBase.Account.Snapshot, accountIdentifier: Data) async throws
        func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.Snapshot?
        func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.Snapshot, accountIdentifier: Data) async throws
        func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.Snapshot?
        func wipeAll() async throws
    }
}
