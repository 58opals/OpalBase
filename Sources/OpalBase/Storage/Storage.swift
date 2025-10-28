// Storage.swift

import Foundation

public actor Storage {
    public enum Error: Swift.Error, Sendable {
        case directoryCreationFailed(URL, Swift.Error)
        case dataReadFailed(URL, Swift.Error)
        case dataWriteFailed(URL, Swift.Error)
        case secureStoreUnavailable
        case secureStoreFailure(Swift.Error)
    }
    
    public struct Configuration: Sendable {
        public var directory: URL?
        public var isMemoryOnly: Bool
        public var filename: String
        
        public init(directory: URL? = nil, isMemoryOnly: Bool = false, filename: String = "opal-storage.json") {
            self.directory = directory
            self.isMemoryOnly = isMemoryOnly
            self.filename = filename
        }
    }
    
    public struct AccountSnapshot: Codable, Sendable, Hashable {
        public var accountIndex: UInt32
        public var unspentTransactionOutputs: [CachedUnspentTransactionOutput]
        public var lastUpdatedAt: Date
        
        public init(accountIndex: UInt32,
                    unspentTransactionOutputs: [CachedUnspentTransactionOutput],
                    lastUpdatedAt: Date = .now) {
            self.accountIndex = accountIndex
            self.unspentTransactionOutputs = unspentTransactionOutputs
            self.lastUpdatedAt = lastUpdatedAt
        }
    }
    
    public struct CachedUnspentTransactionOutput: Codable, Sendable, Hashable {
        public var transactionHash: Data
        public var outputIndex: UInt32
        public var value: UInt64
        public var lockingScript: Data
        
        public init(transactionHash: Data, outputIndex: UInt32, value: UInt64, lockingScript: Data) {
            self.transactionHash = transactionHash
            self.outputIndex = outputIndex
            self.value = value
            self.lockingScript = lockingScript
        }
        
        public init(unspentTransactionOutput: Transaction.Output.Unspent) {
            self.transactionHash = unspentTransactionOutput.previousTransactionHash.naturalOrder
            self.outputIndex = unspentTransactionOutput.previousTransactionOutputIndex
            self.value = unspentTransactionOutput.value
            self.lockingScript = unspentTransactionOutput.lockingScript
        }
        
        public func makeTransactionOutput() -> Transaction.Output.Unspent {
            Transaction.Output.Unspent(value: value,
                                       lockingScript: lockingScript,
                                       previousTransactionHash: .init(naturalOrder: transactionHash),
                                       previousTransactionOutputIndex: outputIndex)
        }
    }
    
    private struct Snapshot: Codable, Sendable {
        var accounts: [UInt32: AccountSnapshot] = .init()
    }
    
    private let fileURL: URL?
    private let mnemonicStore: MnemonicStore?
    private var snapshot: Snapshot
    
    public init(configuration: Configuration = .init(), mnemonicStore: MnemonicStore? = nil) async throws {
        self.mnemonicStore = mnemonicStore
        if configuration.isMemoryOnly {
            self.fileURL = nil
            self.snapshot = .init()
            return
        }
        
        let directory: URL
        if let configuredDirectory = configuration.directory {
            directory = configuredDirectory
        } else {
            if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                directory = applicationSupport
            } else {
                directory = FileManager.default.temporaryDirectory
            }
        }
        
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw Error.directoryCreationFailed(directory, error)
        }
        
        let resolvedURL = directory.appendingPathComponent(configuration.filename)
        self.fileURL = resolvedURL
        
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            do {
                let data = try Data(contentsOf: resolvedURL)
                let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
                self.snapshot = decoded
            } catch {
                throw Error.dataReadFailed(resolvedURL, error)
            }
        } else {
            self.snapshot = .init()
            try await persistSnapshot()
        }
    }
    public func loadAccountSnapshot(for accountIndex: UInt32) -> AccountSnapshot? {
        snapshot.accounts[accountIndex]
    }
    
    public func loadUnspentTransactionOutputs(for accountIndex: UInt32) throws -> [Transaction.Output.Unspent] {
        guard let cached = snapshot.accounts[accountIndex]?.unspentTransactionOutputs else { return .init() }
        return cached.map { $0.makeTransactionOutput() }
    }
    
    public func replaceUnspentTransactionOutputs(_ unspentTransactionOutputs: [Transaction.Output.Unspent],
                                                 for accountIndex: UInt32) async throws {
        let cached = unspentTransactionOutputs.map(CachedUnspentTransactionOutput.init)
        let accountSnapshot = AccountSnapshot(accountIndex: accountIndex,
                                              unspentTransactionOutputs: cached,
                                              lastUpdatedAt: .now)
        snapshot.accounts[accountIndex] = accountSnapshot
        try await persistSnapshot()
    }
    
    public func removeAccount(_ accountIndex: UInt32) async throws {
        snapshot.accounts.removeValue(forKey: accountIndex)
        try await persistSnapshot()
    }
    
    public func clear() async throws {
        snapshot = .init()
        try await persistSnapshot()
    }
    
    public func loadBalance(for accountIndex: UInt32) throws -> UInt64 {
        try loadUnspentTransactionOutputs(for: accountIndex).reduce(0) { $0 + $1.value }
    }
    
    public func saveMnemonic(_ mnemonic: Mnemonic) throws {
        guard let mnemonicStore else { throw Error.secureStoreUnavailable }
        do {
            try mnemonicStore.saveMnemonic(mnemonic)
        } catch {
            throw Error.secureStoreFailure(error)
        }
    }
    
    public func loadMnemonic() throws -> Mnemonic? {
        guard let mnemonicStore else { throw Error.secureStoreUnavailable }
        do {
            return try mnemonicStore.loadMnemonic()
        } catch {
            throw Error.secureStoreFailure(error)
        }
    }
    
    public func removeMnemonic() throws {
        guard let mnemonicStore else { throw Error.secureStoreUnavailable }
        do {
            try mnemonicStore.removeMnemonic()
        } catch {
            throw Error.secureStoreFailure(error)
        }
    }
    
    public func hasMnemonic() throws -> Bool {
        guard let mnemonicStore else { throw Error.secureStoreUnavailable }
        do {
            return try mnemonicStore.hasMnemonic()
        } catch {
            throw Error.secureStoreFailure(error)
        }
    }
    
    private func persistSnapshot() async throws {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw Error.dataWriteFailed(fileURL, error)
        }
    }
}
