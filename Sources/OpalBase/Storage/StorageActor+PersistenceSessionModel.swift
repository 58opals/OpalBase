// StorageActor+PersistenceSessionModel.swift

import Foundation

extension StorageActor {
    public struct PersistenceSessionModel: Sendable {
        public typealias ProgressHandler = @Sendable (ProgressModel) async -> Void
        
        private let ports: StorageActor.PortsModel
        private let progressHandler: ProgressHandler
        
        public init(storage: StorageActor, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.init(ports: storage.makePorts(), progressHandler: progressHandler)
        }
        
        public init(ports: StorageActor.PortsModel, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.ports = ports
            self.progressHandler = progressHandler
        }
        
        public init(operations: OperationsModel, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.init(ports: .init(operations: operations), progressHandler: progressHandler)
        }
        
        @discardableResult
        public func save(wallet: WalletActor, fallbackToPlaintext: Bool = true) async throws -> StorageActor.SecurityModel.ProtectionMode {
            let snapshot = await wallet.makeSnapshot()
            var accountIdentifiers: [UInt32: Data] = .init(minimumCapacity: snapshot.accounts.count)
            for accountSnapshot in snapshot.accounts {
                let account = try await wallet.fetchAccount(at: accountSnapshot.accountUnhardenedIndex)
                let identifier = account.id
                accountIdentifiers[accountSnapshot.accountUnhardenedIndex] = identifier
            }
            return try await save(snapshot: snapshot,
                                  accountIdentifiers: accountIdentifiers,
                                  fallbackToPlaintext: fallbackToPlaintext)
        }
        
        @discardableResult
        func save(snapshot: WalletActor.SnapshotModel,
                  accountIdentifiers: [UInt32: Data],
                  fallbackToPlaintext: Bool = true) async throws -> StorageActor.SecurityModel.ProtectionMode {
            await progressHandler(.beganSave)
            try await ports.snapshotPersistence.saveWalletSnapshot(snapshot)
            await progressHandler(.savedWalletSnapshot)
            
            for accountSnapshot in snapshot.accounts {
                guard let identifier = accountIdentifiers[accountSnapshot.accountUnhardenedIndex] else {
                    throw StorageActor.Error.missingAccountIdentifier(accountSnapshot.accountUnhardenedIndex)
                }
                try await ports.snapshotPersistence.saveAccountSnapshot(accountSnapshot, accountIdentifier: identifier)
                await progressHandler(.savedAccount(identifier: identifier,
                                                    unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
                try await ports.snapshotPersistence.saveAddressBookSnapshot(accountSnapshot.addressBook,
                                                                            accountIdentifier: identifier)
                await progressHandler(.savedAddressBook(identifier: identifier,
                                                        unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
            }
            
            let mnemonic = StorageActor.MnemonicModel(words: snapshot.words, passphrase: snapshot.passphrase)
            let protectionMode = try await ports.secretAccess.saveMnemonic(mnemonic, fallbackToPlaintext: fallbackToPlaintext)
            await progressHandler(.savedMnemonic(mode: protectionMode))
            await progressHandler(.finishedSave(mode: protectionMode))
            return protectionMode
        }
        
        public func restore(accountIdentifiers: [Data]) async throws -> RestoredState {
            await progressHandler(.beganRestore)
            let walletSnapshot = try await ports.snapshotPersistence.loadWalletSnapshot()
            await progressHandler(.loadedWalletSnapshot(found: walletSnapshot != nil))
            
            var accountSnapshots: [Data: AccountActor.SnapshotModel] = .init(minimumCapacity: accountIdentifiers.count)
            var addressBookSnapshots: [Data: AddressModel.BookActor.SnapshotModel] = .init(minimumCapacity: accountIdentifiers.count)
            
            for identifier in accountIdentifiers {
                if let snapshot = try await ports.snapshotPersistence.loadAccountSnapshot(accountIdentifier: identifier) {
                    accountSnapshots[identifier] = snapshot
                    await progressHandler(.loadedAccount(identifier: identifier, found: true))
                } else {
                    await progressHandler(.loadedAccount(identifier: identifier, found: false))
                }
                
                if let snapshot = try await ports.snapshotPersistence.loadAddressBookSnapshot(accountIdentifier: identifier) {
                    addressBookSnapshots[identifier] = snapshot
                    await progressHandler(.loadedAddressBook(identifier: identifier, found: true))
                } else {
                    await progressHandler(.loadedAddressBook(identifier: identifier, found: false))
                }
            }
            
            let mnemonicState = try await ports.secretAccess.loadMnemonicState()
            await progressHandler(.loadedMnemonic(mode: mnemonicState?.protectionMode))
            await progressHandler(.finishedRestore)
            
            return RestoredState(walletSnapshot: walletSnapshot,
                                 accountSnapshots: accountSnapshots,
                                 addressBookSnapshots: addressBookSnapshots,
                                 mnemonic: mnemonicState?.mnemonic,
                                 mnemonicProtectionMode: mnemonicState?.protectionMode)
        }
        
        public func wipe() async throws {
            await progressHandler(.beganWipe)
            try await ports.snapshotPersistence.wipeAll()
            await progressHandler(.finishedWipe)
        }
    }
}

extension StorageActor.PersistenceSessionModel {
    public struct OperationsModel: Sendable {
        public var walletSnapshotSaver: @Sendable (WalletActor.SnapshotModel) async throws -> Void
        public var walletSnapshotLoader: @Sendable () async throws -> WalletActor.SnapshotModel?
        public var accountSnapshotSaver: @Sendable (AccountActor.SnapshotModel, Data) async throws -> Void
        public var accountSnapshotLoader: @Sendable (Data) async throws -> AccountActor.SnapshotModel?
        public var addressBookSnapshotSaver: @Sendable (AddressModel.BookActor.SnapshotModel, Data) async throws -> Void
        public var addressBookSnapshotLoader: @Sendable (Data) async throws -> AddressModel.BookActor.SnapshotModel?
        public var mnemonicSaver: @Sendable (StorageActor.MnemonicModel, Bool) async throws -> StorageActor.SecurityModel.ProtectionMode
        public var mnemonicStateLoader: @Sendable () async throws -> (mnemonic: StorageActor.MnemonicModel, protectionMode: StorageActor.SecurityModel.ProtectionMode)?
        public var wipeAllOperation: @Sendable () async throws -> Void
        
        public init(
            walletSnapshotSaver: @escaping @Sendable (WalletActor.SnapshotModel) async throws -> Void,
            walletSnapshotLoader: @escaping @Sendable () async throws -> WalletActor.SnapshotModel?,
            accountSnapshotSaver: @escaping @Sendable (AccountActor.SnapshotModel, Data) async throws -> Void,
            accountSnapshotLoader: @escaping @Sendable (Data) async throws -> AccountActor.SnapshotModel?,
            addressBookSnapshotSaver: @escaping @Sendable (AddressModel.BookActor.SnapshotModel, Data) async throws -> Void,
            addressBookSnapshotLoader: @escaping @Sendable (Data) async throws -> AddressModel.BookActor.SnapshotModel?,
            mnemonicSaver: @escaping @Sendable (StorageActor.MnemonicModel, Bool) async throws -> StorageActor.SecurityModel.ProtectionMode,
            mnemonicStateLoader: @escaping @Sendable () async throws -> (mnemonic: StorageActor.MnemonicModel, protectionMode: StorageActor.SecurityModel.ProtectionMode)?,
            wipeAllOperation: @escaping @Sendable () async throws -> Void
        ) {
            self.walletSnapshotSaver = walletSnapshotSaver
            self.walletSnapshotLoader = walletSnapshotLoader
            self.accountSnapshotSaver = accountSnapshotSaver
            self.accountSnapshotLoader = accountSnapshotLoader
            self.addressBookSnapshotSaver = addressBookSnapshotSaver
            self.addressBookSnapshotLoader = addressBookSnapshotLoader
            self.mnemonicSaver = mnemonicSaver
            self.mnemonicStateLoader = mnemonicStateLoader
            self.wipeAllOperation = wipeAllOperation
        }
    }
    
    public enum ProgressModel: Sendable, Equatable {
        case beganSave
        case savedWalletSnapshot
        case savedAccount(identifier: Data, unhardenedIndex: UInt32)
        case savedAddressBook(identifier: Data, unhardenedIndex: UInt32)
        case savedMnemonic(mode: StorageActor.SecurityModel.ProtectionMode)
        case finishedSave(mode: StorageActor.SecurityModel.ProtectionMode)
        case beganRestore
        case loadedWalletSnapshot(found: Bool)
        case loadedAccount(identifier: Data, found: Bool)
        case loadedAddressBook(identifier: Data, found: Bool)
        case loadedMnemonic(mode: StorageActor.SecurityModel.ProtectionMode?)
        case finishedRestore
        case beganWipe
        case finishedWipe
    }
    
    public struct RestoredState: Sendable {
        public let walletSnapshot: WalletActor.SnapshotModel?
        public let accountSnapshots: [Data: AccountActor.SnapshotModel]
        public let addressBookSnapshots: [Data: AddressModel.BookActor.SnapshotModel]
        public let mnemonic: StorageActor.MnemonicModel?
        public let mnemonicProtectionMode: StorageActor.SecurityModel.ProtectionMode?
        
        public init(walletSnapshot: WalletActor.SnapshotModel?,
                    accountSnapshots: [Data: AccountActor.SnapshotModel],
                    addressBookSnapshots: [Data: AddressModel.BookActor.SnapshotModel],
                    mnemonic: StorageActor.MnemonicModel?,
                    mnemonicProtectionMode: StorageActor.SecurityModel.ProtectionMode?) {
            self.walletSnapshot = walletSnapshot
            self.accountSnapshots = accountSnapshots
            self.addressBookSnapshots = addressBookSnapshots
            self.mnemonic = mnemonic
            self.mnemonicProtectionMode = mnemonicProtectionMode
        }
    }
}
