// OpalBase+Storage+SnapshotStore.swift

import Foundation

extension _OpalBase.Storage {
    public struct SnapshotStore: Sendable {
        private let saveWalletSnapshotHandler: @Sendable (OpalBase.Wallet.Snapshot) async throws -> Void
        private let loadWalletSnapshotHandler: @Sendable () async throws -> OpalBase.Wallet.Snapshot?
        private let saveAccountSnapshotHandler: @Sendable (OpalBase.Account.Snapshot, Data) async throws -> Void
        private let loadAccountSnapshotHandler: @Sendable (Data) async throws -> OpalBase.Account.Snapshot?
        private let saveAddressBookSnapshotHandler: @Sendable (OpalBase.Address.Book.Snapshot, Data) async throws -> Void
        private let loadAddressBookSnapshotHandler: @Sendable (Data) async throws -> OpalBase.Address.Book.Snapshot?
        private let wipeAllHandler: @Sendable () async throws -> Void

        public init(
            saveWalletSnapshot: @escaping @Sendable (OpalBase.Wallet.Snapshot) async throws -> Void,
            loadWalletSnapshot: @escaping @Sendable () async throws -> OpalBase.Wallet.Snapshot?,
            saveAccountSnapshot: @escaping @Sendable (OpalBase.Account.Snapshot, Data) async throws -> Void,
            loadAccountSnapshot: @escaping @Sendable (Data) async throws -> OpalBase.Account.Snapshot?,
            saveAddressBookSnapshot: @escaping @Sendable (OpalBase.Address.Book.Snapshot, Data) async throws -> Void,
            loadAddressBookSnapshot: @escaping @Sendable (Data) async throws -> OpalBase.Address.Book.Snapshot?,
            wipeAll: @escaping @Sendable () async throws -> Void
        ) {
            self.saveWalletSnapshotHandler = saveWalletSnapshot
            self.loadWalletSnapshotHandler = loadWalletSnapshot
            self.saveAccountSnapshotHandler = saveAccountSnapshot
            self.loadAccountSnapshotHandler = loadAccountSnapshot
            self.saveAddressBookSnapshotHandler = saveAddressBookSnapshot
            self.loadAddressBookSnapshotHandler = loadAddressBookSnapshot
            self.wipeAllHandler = wipeAll
        }

        public func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws {
            try await saveWalletSnapshotHandler(snapshot)
        }

        public func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot? {
            try await loadWalletSnapshotHandler()
        }

        public func saveAccountSnapshot(_ snapshot: OpalBase.Account.Snapshot, accountIdentifier: Data) async throws {
            try await saveAccountSnapshotHandler(snapshot, accountIdentifier)
        }

        public func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.Snapshot? {
            try await loadAccountSnapshotHandler(accountIdentifier)
        }

        public func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.Snapshot, accountIdentifier: Data) async throws {
            try await saveAddressBookSnapshotHandler(snapshot, accountIdentifier)
        }

        public func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.Snapshot? {
            try await loadAddressBookSnapshotHandler(accountIdentifier)
        }

        public func wipeAll() async throws {
            try await wipeAllHandler()
        }
    }

    public nonisolated func makeSnapshotStore() -> SnapshotStore {
        SnapshotStore(
            saveWalletSnapshot: saveWalletSnapshot(_:),
            loadWalletSnapshot: loadWalletSnapshot,
            saveAccountSnapshot: saveAccountSnapshot(_:accountIdentifier:),
            loadAccountSnapshot: loadAccountSnapshot(accountIdentifier:),
            saveAddressBookSnapshot: saveAddressBookSnapshot(_:accountIdentifier:),
            loadAddressBookSnapshot: loadAddressBookSnapshot(accountIdentifier:),
            wipeAll: wipeAll
        )
    }
}
