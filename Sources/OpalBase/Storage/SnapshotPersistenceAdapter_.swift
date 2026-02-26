// SnapshotPersistencePort_.swift

import Foundation

public protocol SnapshotPersistenceAdapter: Sendable {
    func saveWalletSnapshot(_ snapshot: WalletActor.SnapshotModel) async throws
    func loadWalletSnapshot() async throws -> WalletActor.SnapshotModel?
    func saveAccountSnapshot(_ snapshot: AccountActor.SnapshotModel, accountIdentifier: Data) async throws
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> AccountActor.SnapshotModel?
    func saveAddressBookSnapshot(_ snapshot: AddressModel.BookActor.SnapshotModel, accountIdentifier: Data) async throws
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> AddressModel.BookActor.SnapshotModel?
    func wipeAll() async throws
}
