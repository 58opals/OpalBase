// OpalBase+Storage+PersistenceSession.swift

import Foundation

extension _OpalBase.Storage {
    public struct PersistenceSession: Sendable {
        public typealias ProgressHandler = @Sendable (Progress) async -> Void
        
        private let snapshotStore: OpalBase.Storage.SnapshotStore
        private let storedMnemonicStore: OpalBase.Storage.StoredMnemonicStore
        private let progressHandler: ProgressHandler
        
        public init(storage: OpalBase.Storage, progressHandler: @escaping ProgressHandler = { _ in }) {
            self.init(snapshotStore: storage.makeSnapshotStore(),
                      storedMnemonicStore: storage.makeStoredMnemonicStore(),
                      progressHandler: progressHandler)
        }
        
        public init(snapshotStore: OpalBase.Storage.SnapshotStore,
                    storedMnemonicStore: OpalBase.Storage.StoredMnemonicStore,
                    progressHandler: @escaping ProgressHandler = { _ in }) {
            self.snapshotStore = snapshotStore
            self.storedMnemonicStore = storedMnemonicStore
            self.progressHandler = progressHandler
        }
        
        @discardableResult
        public func save(wallet: OpalBase.Wallet, fallbackToPlaintext: Bool = true) async throws -> OpalBase.Storage.Security.ProtectionMode {
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
                  fallbackToPlaintext: Bool = true) async throws -> OpalBase.Storage.Security.ProtectionMode {
            await progressHandler(.beganSave)
            try await snapshotStore.saveWalletSnapshot(snapshot)
            await progressHandler(.savedWalletSnapshot)
            
            for accountSnapshot in snapshot.accounts {
                guard let identifier = accountIdentifiers[accountSnapshot.accountUnhardenedIndex] else {
                    throw OpalBase.Storage.Error.missingAccountIdentifier(accountSnapshot.accountUnhardenedIndex)
                }
                try await snapshotStore.saveAccountSnapshot(accountSnapshot, accountIdentifier: identifier)
                await progressHandler(.savedAccount(identifier: identifier,
                                                    unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
                try await snapshotStore.saveAddressBookSnapshot(accountSnapshot.addressBook,
                                                                accountIdentifier: identifier)
                await progressHandler(.savedAddressBook(identifier: identifier,
                                                        unhardenedIndex: accountSnapshot.accountUnhardenedIndex))
            }
            
            let mnemonic = OpalBase.Storage.StoredMnemonic(words: snapshot.words, passphrase: snapshot.passphrase)
            let protectionMode = try await storedMnemonicStore.saveMnemonic(mnemonic, fallbackToPlaintext: fallbackToPlaintext)
            await progressHandler(.savedMnemonic(mode: protectionMode))
            await progressHandler(.finishedSave(mode: protectionMode))
            return protectionMode
        }
        
        public func restore(accountIdentifiers: [Data]) async throws -> RestoredState {
            await progressHandler(.beganRestore)
            let walletSnapshot = try await snapshotStore.loadWalletSnapshot()
            await progressHandler(.loadedWalletSnapshot(found: walletSnapshot != nil))
            
            var accountSnapshots: [Data: OpalBase.Account.Snapshot] = .init(minimumCapacity: accountIdentifiers.count)
            var addressBookSnapshots: [Data: OpalBase.Address.Book.Snapshot] = .init(minimumCapacity: accountIdentifiers.count)
            
            for identifier in accountIdentifiers {
                if let snapshot = try await snapshotStore.loadAccountSnapshot(accountIdentifier: identifier) {
                    accountSnapshots[identifier] = snapshot
                    await progressHandler(.loadedAccount(identifier: identifier, found: true))
                } else {
                    await progressHandler(.loadedAccount(identifier: identifier, found: false))
                }
                
                if let snapshot = try await snapshotStore.loadAddressBookSnapshot(accountIdentifier: identifier) {
                    addressBookSnapshots[identifier] = snapshot
                    await progressHandler(.loadedAddressBook(identifier: identifier, found: true))
                } else {
                    await progressHandler(.loadedAddressBook(identifier: identifier, found: false))
                }
            }
            
            let mnemonicState = try await storedMnemonicStore.loadMnemonicState()
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
            try await snapshotStore.wipeAll()
            await progressHandler(.finishedWipe)
        }
    }
}

extension _OpalBase.Storage.PersistenceSession {
    public enum Progress: Sendable, Equatable {
        case beganSave
        case savedWalletSnapshot
        case savedAccount(identifier: Data, unhardenedIndex: UInt32)
        case savedAddressBook(identifier: Data, unhardenedIndex: UInt32)
        case savedMnemonic(mode: OpalBase.Storage.Security.ProtectionMode)
        case finishedSave(mode: OpalBase.Storage.Security.ProtectionMode)
        case beganRestore
        case loadedWalletSnapshot(found: Bool)
        case loadedAccount(identifier: Data, found: Bool)
        case loadedAddressBook(identifier: Data, found: Bool)
        case loadedMnemonic(mode: OpalBase.Storage.Security.ProtectionMode?)
        case finishedRestore
        case beganWipe
        case finishedWipe
    }
    
    public struct RestoredState: Sendable {
        public let walletSnapshot: OpalBase.Wallet.Snapshot?
        public let accountSnapshots: [Data: OpalBase.Account.Snapshot]
        public let addressBookSnapshots: [Data: OpalBase.Address.Book.Snapshot]
        public let mnemonic: OpalBase.Storage.StoredMnemonic?
        public let mnemonicProtectionMode: OpalBase.Storage.Security.ProtectionMode?
        
        public init(walletSnapshot: OpalBase.Wallet.Snapshot?,
                    accountSnapshots: [Data: OpalBase.Account.Snapshot],
                    addressBookSnapshots: [Data: OpalBase.Address.Book.Snapshot],
                    mnemonic: OpalBase.Storage.StoredMnemonic?,
                    mnemonicProtectionMode: OpalBase.Storage.Security.ProtectionMode?) {
            self.walletSnapshot = walletSnapshot
            self.accountSnapshots = accountSnapshots
            self.addressBookSnapshots = addressBookSnapshots
            self.mnemonic = mnemonic
            self.mnemonicProtectionMode = mnemonicProtectionMode
        }
    }
}
