// OpalBase+Storage+PersistenceSessionModel.swift

import Foundation

extension _OpalBase.Storage {
    public struct PersistenceSessionModel: Sendable {
        public typealias ProgressHandler = @Sendable (ProgressModel) async -> Void
        
        private let ports: OpalBase.Storage.PortsModel
        private let progressHandler: ProgressHandler
        
        public init(storage: OpalBase.Storage, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.init(ports: storage.makePorts(), progressHandler: progressHandler)
        }
        
        public init(ports: OpalBase.Storage.PortsModel, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.ports = ports
            self.progressHandler = progressHandler
        }
        
        public init(operations: OperationsModel, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.init(ports: .init(operations: operations), progressHandler: progressHandler)
        }
        
        @discardableResult
        public func save(wallet: OpalBase.Wallet, fallbackToPlaintext: Bool = true) async throws -> OpalBase.Storage.SecurityModel.ProtectionMode {
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
        func save(snapshot: OpalBase.Wallet.Snapshot,
                  accountIdentifiers: [UInt32: Data],
                  fallbackToPlaintext: Bool = true) async throws -> OpalBase.Storage.SecurityModel.ProtectionMode {
            await progressHandler(.beganSave)
            try await ports.snapshotPersistence.saveWalletSnapshot(snapshot)
            await progressHandler(.savedWalletSnapshot)
            
            for accountSnapshot in snapshot.accounts {
                guard let identifier = accountIdentifiers[accountSnapshot.accountUnhardenedIndex] else {
                    throw OpalBase.Storage.Error.missingAccountIdentifier(accountSnapshot.accountUnhardenedIndex)
                }
                try await ports.snapshotPersistence.saveAccountSnapshot(accountSnapshot, accountIdentifier: identifier)
                await progressHandler(.savedAccount(identifier: identifier,
                                                    unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
                try await ports.snapshotPersistence.saveAddressBookSnapshot(accountSnapshot.addressBook,
                                                                            accountIdentifier: identifier)
                await progressHandler(.savedAddressBook(identifier: identifier,
                                                        unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
            }
            
            let mnemonic = OpalBase.Storage.Mnemonic(words: snapshot.words, passphrase: snapshot.passphrase)
            let protectionMode = try await ports.secretAccess.saveMnemonic(mnemonic, fallbackToPlaintext: fallbackToPlaintext)
            await progressHandler(.savedMnemonic(mode: protectionMode))
            await progressHandler(.finishedSave(mode: protectionMode))
            return protectionMode
        }
        
        public func restore(accountIdentifiers: [Data]) async throws -> RestoredState {
            await progressHandler(.beganRestore)
            let walletSnapshot = try await ports.snapshotPersistence.loadWalletSnapshot()
            await progressHandler(.loadedWalletSnapshot(found: walletSnapshot != nil))
            
            var accountSnapshots: [Data: OpalBase.Account.SnapshotModel] = .init(minimumCapacity: accountIdentifiers.count)
            var addressBookSnapshots: [Data: OpalBase.Address.Book.SnapshotModel] = .init(minimumCapacity: accountIdentifiers.count)
            
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

extension _OpalBase.Storage.PersistenceSessionModel {
    public struct OperationsModel: Sendable {
        public var walletSnapshotSaver: @Sendable (OpalBase.Wallet.Snapshot) async throws -> Void
        public var walletSnapshotLoader: @Sendable () async throws -> OpalBase.Wallet.Snapshot?
        public var accountSnapshotSaver: @Sendable (OpalBase.Account.SnapshotModel, Data) async throws -> Void
        public var accountSnapshotLoader: @Sendable (Data) async throws -> OpalBase.Account.SnapshotModel?
        public var addressBookSnapshotSaver: @Sendable (OpalBase.Address.Book.SnapshotModel, Data) async throws -> Void
        public var addressBookSnapshotLoader: @Sendable (Data) async throws -> OpalBase.Address.Book.SnapshotModel?
        public var mnemonicSaver: @Sendable (OpalBase.Storage.Mnemonic, Bool) async throws -> OpalBase.Storage.SecurityModel.ProtectionMode
        public var mnemonicStateLoader: @Sendable () async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: OpalBase.Storage.SecurityModel.ProtectionMode)?
        public var wipeAllOperation: @Sendable () async throws -> Void
        
        public init(
            walletSnapshotSaver: @escaping @Sendable (OpalBase.Wallet.Snapshot) async throws -> Void,
            walletSnapshotLoader: @escaping @Sendable () async throws -> OpalBase.Wallet.Snapshot?,
            accountSnapshotSaver: @escaping @Sendable (OpalBase.Account.SnapshotModel, Data) async throws -> Void,
            accountSnapshotLoader: @escaping @Sendable (Data) async throws -> OpalBase.Account.SnapshotModel?,
            addressBookSnapshotSaver: @escaping @Sendable (OpalBase.Address.Book.SnapshotModel, Data) async throws -> Void,
            addressBookSnapshotLoader: @escaping @Sendable (Data) async throws -> OpalBase.Address.Book.SnapshotModel?,
            mnemonicSaver: @escaping @Sendable (OpalBase.Storage.Mnemonic, Bool) async throws -> OpalBase.Storage.SecurityModel.ProtectionMode,
            mnemonicStateLoader: @escaping @Sendable () async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: OpalBase.Storage.SecurityModel.ProtectionMode)?,
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
        case savedMnemonic(mode: OpalBase.Storage.SecurityModel.ProtectionMode)
        case finishedSave(mode: OpalBase.Storage.SecurityModel.ProtectionMode)
        case beganRestore
        case loadedWalletSnapshot(found: Bool)
        case loadedAccount(identifier: Data, found: Bool)
        case loadedAddressBook(identifier: Data, found: Bool)
        case loadedMnemonic(mode: OpalBase.Storage.SecurityModel.ProtectionMode?)
        case finishedRestore
        case beganWipe
        case finishedWipe
    }
    
    public struct RestoredState: Sendable {
        public let walletSnapshot: OpalBase.Wallet.Snapshot?
        public let accountSnapshots: [Data: OpalBase.Account.SnapshotModel]
        public let addressBookSnapshots: [Data: OpalBase.Address.Book.SnapshotModel]
        public let mnemonic: OpalBase.Storage.Mnemonic?
        public let mnemonicProtectionMode: OpalBase.Storage.SecurityModel.ProtectionMode?
        
        public init(walletSnapshot: OpalBase.Wallet.Snapshot?,
                    accountSnapshots: [Data: OpalBase.Account.SnapshotModel],
                    addressBookSnapshots: [Data: OpalBase.Address.Book.SnapshotModel],
                    mnemonic: OpalBase.Storage.Mnemonic?,
                    mnemonicProtectionMode: OpalBase.Storage.SecurityModel.ProtectionMode?) {
            self.walletSnapshot = walletSnapshot
            self.accountSnapshots = accountSnapshots
            self.addressBookSnapshots = addressBookSnapshots
            self.mnemonic = mnemonic
            self.mnemonicProtectionMode = mnemonicProtectionMode
        }
    }
}
