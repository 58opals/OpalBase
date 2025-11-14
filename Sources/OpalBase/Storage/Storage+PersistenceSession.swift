// Storage+PersistenceSession.swift

import Foundation

extension Storage {
    public struct PersistenceSession: Sendable {
        public typealias ProgressHandler = @Sendable (Progress) async -> Void
        
        private let operations: Operations
        private let progressHandler: ProgressHandler
        
        public init(storage: Storage, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.operations = .makeDefault(using: storage)
            self.progressHandler = progressHandler
        }
        
        public init(operations: Operations, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.operations = operations
            self.progressHandler = progressHandler
        }
        
        @discardableResult
        public func save(wallet: Wallet, fallbackToPlaintext: Bool = true) async throws -> Storage.Security.ProtectionMode {
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
        func save(snapshot: Wallet.Snapshot,
                  accountIdentifiers: [UInt32: Data],
                  fallbackToPlaintext: Bool = true) async throws -> Storage.Security.ProtectionMode {
            await progressHandler(.beganSave)
            try await operations.saveWalletSnapshot(snapshot)
            await progressHandler(.savedWalletSnapshot)
            
            for accountSnapshot in snapshot.accounts {
                guard let identifier = accountIdentifiers[accountSnapshot.accountUnhardenedIndex] else {
                    throw Storage.Error.missingAccountIdentifier(accountSnapshot.accountUnhardenedIndex)
                }
                try await operations.saveAccountSnapshot(accountSnapshot, identifier)
                await progressHandler(.savedAccount(identifier: identifier,
                                                    unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
                try await operations.saveAddressBookSnapshot(accountSnapshot.addressBook, identifier)
                await progressHandler(.savedAddressBook(identifier: identifier,
                                                        unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
            }
            
            let mnemonic = Storage.Mnemonic(words: snapshot.words, passphrase: snapshot.passphrase)
            let protectionMode = try await operations.saveMnemonic(mnemonic, fallbackToPlaintext)
            await progressHandler(.savedMnemonic(mode: protectionMode))
            await progressHandler(.finishedSave(mode: protectionMode))
            return protectionMode
        }
        
        public func restore(accountIdentifiers: [Data]) async throws -> RestoredState {
            await progressHandler(.beganRestore)
            let walletSnapshot = try await operations.loadWalletSnapshot()
            await progressHandler(.loadedWalletSnapshot(found: walletSnapshot != nil))
            
            var accountSnapshots: [Data: Account.Snapshot] = .init(minimumCapacity: accountIdentifiers.count)
            var addressBookSnapshots: [Data: Address.Book.Snapshot] = .init(minimumCapacity: accountIdentifiers.count)
            
            for identifier in accountIdentifiers {
                if let snapshot = try await operations.loadAccountSnapshot(identifier) {
                    accountSnapshots[identifier] = snapshot
                    await progressHandler(.loadedAccount(identifier: identifier, found: true))
                } else {
                    await progressHandler(.loadedAccount(identifier: identifier, found: false))
                }
                
                if let snapshot = try await operations.loadAddressBookSnapshot(identifier) {
                    addressBookSnapshots[identifier] = snapshot
                    await progressHandler(.loadedAddressBook(identifier: identifier, found: true))
                } else {
                    await progressHandler(.loadedAddressBook(identifier: identifier, found: false))
                }
            }
            
            let mnemonicState = try await operations.loadMnemonicState()
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
            try await operations.wipeAll()
            await progressHandler(.finishedWipe)
        }
    }
}

private extension Storage.PersistenceSession.Operations {
    static func makeDefault(using storage: Storage) -> Self {
        .init(saveWalletSnapshot: { snapshot in
            try await storage.saveWalletSnapshot(snapshot)
        },
              loadWalletSnapshot: {
            try await storage.loadWalletSnapshot()
        },
              saveAccountSnapshot: { snapshot, identifier in
            try await storage.saveAccountSnapshot(snapshot, accountIdentifier: identifier)
        },
              loadAccountSnapshot: { identifier in
            try await storage.loadAccountSnapshot(accountIdentifier: identifier)
        },
              saveAddressBookSnapshot: { snapshot, identifier in
            try await storage.saveAddressBookSnapshot(snapshot, accountIdentifier: identifier)
        },
              loadAddressBookSnapshot: { identifier in
            try await storage.loadAddressBookSnapshot(accountIdentifier: identifier)
        },
              saveMnemonic: { mnemonic, fallback in
            try await storage.saveMnemonic(mnemonic, fallbackToPlaintext: fallback)
        },
              loadMnemonicState: {
            try await storage.loadMnemonicState()
        },
              wipeAll: {
            try await storage.wipeAll()
        })
    }
}

extension Storage.PersistenceSession {
    public struct Operations: Sendable {
        public var saveWalletSnapshot: @Sendable (Wallet.Snapshot) async throws -> Void
        public var loadWalletSnapshot: @Sendable () async throws -> Wallet.Snapshot?
        public var saveAccountSnapshot: @Sendable (Account.Snapshot, Data) async throws -> Void
        public var loadAccountSnapshot: @Sendable (Data) async throws -> Account.Snapshot?
        public var saveAddressBookSnapshot: @Sendable (Address.Book.Snapshot, Data) async throws -> Void
        public var loadAddressBookSnapshot: @Sendable (Data) async throws -> Address.Book.Snapshot?
        public var saveMnemonic: @Sendable (Storage.Mnemonic, Bool) async throws -> Storage.Security.ProtectionMode
        public var loadMnemonicState: @Sendable () async throws -> (mnemonic: Storage.Mnemonic, protectionMode: Storage.Security.ProtectionMode)?
        public var wipeAll: @Sendable () async throws -> Void
        
        public init(
            saveWalletSnapshot: @escaping @Sendable (Wallet.Snapshot) async throws -> Void,
            loadWalletSnapshot: @escaping @Sendable () async throws -> Wallet.Snapshot?,
            saveAccountSnapshot: @escaping @Sendable (Account.Snapshot, Data) async throws -> Void,
            loadAccountSnapshot: @escaping @Sendable (Data) async throws -> Account.Snapshot?,
            saveAddressBookSnapshot: @escaping @Sendable (Address.Book.Snapshot, Data) async throws -> Void,
            loadAddressBookSnapshot: @escaping @Sendable (Data) async throws -> Address.Book.Snapshot?,
            saveMnemonic: @escaping @Sendable (Storage.Mnemonic, Bool) async throws -> Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable () async throws -> (mnemonic: Storage.Mnemonic, protectionMode: Storage.Security.ProtectionMode)?,
            wipeAll: @escaping @Sendable () async throws -> Void
        ) {
            self.saveWalletSnapshot = saveWalletSnapshot
            self.loadWalletSnapshot = loadWalletSnapshot
            self.saveAccountSnapshot = saveAccountSnapshot
            self.loadAccountSnapshot = loadAccountSnapshot
            self.saveAddressBookSnapshot = saveAddressBookSnapshot
            self.loadAddressBookSnapshot = loadAddressBookSnapshot
            self.saveMnemonic = saveMnemonic
            self.loadMnemonicState = loadMnemonicState
            self.wipeAll = wipeAll
        }
    }
    
    public enum Progress: Sendable, Equatable {
        case beganSave
        case savedWalletSnapshot
        case savedAccount(identifier: Data, unhardenedIndex: UInt32)
        case savedAddressBook(identifier: Data, unhardenedIndex: UInt32)
        case savedMnemonic(mode: Storage.Security.ProtectionMode)
        case finishedSave(mode: Storage.Security.ProtectionMode)
        case beganRestore
        case loadedWalletSnapshot(found: Bool)
        case loadedAccount(identifier: Data, found: Bool)
        case loadedAddressBook(identifier: Data, found: Bool)
        case loadedMnemonic(mode: Storage.Security.ProtectionMode?)
        case finishedRestore
        case beganWipe
        case finishedWipe
    }
    
    public struct RestoredState: Sendable {
        public let walletSnapshot: Wallet.Snapshot?
        public let accountSnapshots: [Data: Account.Snapshot]
        public let addressBookSnapshots: [Data: Address.Book.Snapshot]
        public let mnemonic: Storage.Mnemonic?
        public let mnemonicProtectionMode: Storage.Security.ProtectionMode?
        
        public init(walletSnapshot: Wallet.Snapshot?,
                    accountSnapshots: [Data: Account.Snapshot],
                    addressBookSnapshots: [Data: Address.Book.Snapshot],
                    mnemonic: Storage.Mnemonic?,
                    mnemonicProtectionMode: Storage.Security.ProtectionMode?) {
            self.walletSnapshot = walletSnapshot
            self.accountSnapshots = accountSnapshots
            self.addressBookSnapshots = addressBookSnapshots
            self.mnemonic = mnemonic
            self.mnemonicProtectionMode = mnemonicProtectionMode
        }
    }
}
