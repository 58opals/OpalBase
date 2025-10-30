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
        public struct TransactionLedger: Codable, Sendable, Hashable {
            public struct Entry: Codable, Sendable, Hashable {
                public enum Status: String, Codable, Sendable {
                    case discovered
                    case pending
                    case confirmed
                    case failed
                }
                
                public enum VerificationStatus: String, Codable, Sendable {
                    case unknown
                    case pending
                    case verified
                    case conflicting
                }
                
                public struct MerkleProof: Codable, Sendable, Hashable {
                    public let blockHeight: UInt32
                    public let position: UInt32
                    public let branch: [Data]
                    public let blockHash: Data?
                    
                    public init(blockHeight: UInt32,
                                position: UInt32,
                                branch: [Data],
                                blockHash: Data?) {
                        self.blockHeight = blockHeight
                        self.position = position
                        self.branch = branch
                        self.blockHash = blockHash
                    }
                }
                
                public var transactionHash: Data
                public var status: Status
                public var confirmationHeight: UInt64?
                public var discoveredAt: Date
                public var confirmedAt: Date?
                public var label: String?
                public var memo: String?
                
                public var verificationStatus: VerificationStatus
                public var merkleProof: MerkleProof?
                public var lastVerifiedHeight: UInt32?
                public var lastCheckedAt: Date?
                
                public init(transactionHash: Data,
                            status: Status,
                            confirmationHeight: UInt64? = nil,
                            discoveredAt: Date,
                            confirmedAt: Date? = nil,
                            label: String? = nil,
                            memo: String? = nil,
                            verificationStatus: VerificationStatus = .unknown,
                            merkleProof: MerkleProof? = nil,
                            lastVerifiedHeight: UInt32? = nil,
                            lastCheckedAt: Date? = nil) {
                    self.transactionHash = transactionHash
                    self.status = status
                    self.confirmationHeight = confirmationHeight
                    self.discoveredAt = discoveredAt
                    self.confirmedAt = confirmedAt
                    self.label = label
                    self.memo = memo
                    self.verificationStatus = verificationStatus
                    self.merkleProof = merkleProof
                    self.lastVerifiedHeight = lastVerifiedHeight
                    self.lastCheckedAt = lastCheckedAt
                }
                
                private enum CodingKeys: String, CodingKey {
                    case transactionHash
                    case status
                    case confirmationHeight
                    case discoveredAt
                    case confirmedAt
                    case label
                    case memo
                    case verificationStatus
                    case merkleProof
                    case lastVerifiedHeight
                    case lastCheckedAt
                }
                
                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    transactionHash = try container.decode(Data.self, forKey: .transactionHash)
                    status = try container.decode(Status.self, forKey: .status)
                    confirmationHeight = try container.decodeIfPresent(UInt64.self, forKey: .confirmationHeight)
                    discoveredAt = try container.decode(Date.self, forKey: .discoveredAt)
                    confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
                    label = try container.decodeIfPresent(String.self, forKey: .label)
                    memo = try container.decodeIfPresent(String.self, forKey: .memo)
                    verificationStatus = try container.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus) ?? .unknown
                    merkleProof = try container.decodeIfPresent(MerkleProof.self, forKey: .merkleProof)
                    lastVerifiedHeight = try container.decodeIfPresent(UInt32.self, forKey: .lastVerifiedHeight)
                    lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
                }
                
                public func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    try container.encode(transactionHash, forKey: .transactionHash)
                    try container.encode(status, forKey: .status)
                    try container.encodeIfPresent(confirmationHeight, forKey: .confirmationHeight)
                    try container.encode(discoveredAt, forKey: .discoveredAt)
                    try container.encodeIfPresent(confirmedAt, forKey: .confirmedAt)
                    try container.encodeIfPresent(label, forKey: .label)
                    try container.encodeIfPresent(memo, forKey: .memo)
                    try container.encode(verificationStatus, forKey: .verificationStatus)
                    try container.encodeIfPresent(merkleProof, forKey: .merkleProof)
                    try container.encodeIfPresent(lastVerifiedHeight, forKey: .lastVerifiedHeight)
                    try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
                }
            }
            
            private var entriesByTransactionHash: [Data: Entry]
            
            public init(entries: [Entry] = .init()) {
                var ledger: [Data: Entry] = .init(minimumCapacity: entries.count)
                for entry in entries {
                    ledger[entry.transactionHash] = entry
                }
                self.entriesByTransactionHash = ledger
            }
            
            public var entries: [Entry] {
                Array(entriesByTransactionHash.values)
            }
            
            public func entry(for transactionHash: Data) -> Entry? {
                entriesByTransactionHash[transactionHash]
            }
            
            public mutating func insert(_ entry: Entry) -> Bool {
                guard entriesByTransactionHash[entry.transactionHash] == nil else { return false }
                entriesByTransactionHash[entry.transactionHash] = entry
                return true
            }
            
            public mutating func update(_ entry: Entry) -> Bool {
                guard entriesByTransactionHash[entry.transactionHash] != nil else { return false }
                entriesByTransactionHash[entry.transactionHash] = entry
                return true
            }
            
            public mutating func removeEntry(for transactionHash: Data) -> Bool {
                guard entriesByTransactionHash.removeValue(forKey: transactionHash) != nil else { return false }
                return true
            }
            
            public static func == (lhs: TransactionLedger, rhs: TransactionLedger) -> Bool {
                lhs.entriesByTransactionHash == rhs.entriesByTransactionHash
            }
            
            public func hash(into hasher: inout Hasher) {
                let sortedEntries = entries.sorted { lhs, rhs in
                    lhs.transactionHash.lexicographicallyPrecedes(rhs.transactionHash)
                }
                for entry in sortedEntries {
                    hasher.combine(entry)
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(entries)
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let decodedEntries = try container.decode([Entry].self)
                self.init(entries: decodedEntries)
            }
        }
        
        public var accountIndex: UInt32
        public var unspentTransactionOutputs: [CachedUnspentTransactionOutput]
        public var lastUpdatedAt: Date
        public var transactionLedger: TransactionLedger
        
        public init(accountIndex: UInt32,
                    unspentTransactionOutputs: [CachedUnspentTransactionOutput],
                    lastUpdatedAt: Date = .now,
                    transactionLedger: TransactionLedger = .init()) {
            self.accountIndex = accountIndex
            self.unspentTransactionOutputs = unspentTransactionOutputs
            self.lastUpdatedAt = lastUpdatedAt
            self.transactionLedger = transactionLedger
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
        let transactionLedger = snapshot.accounts[accountIndex]?.transactionLedger ?? .init()
        let accountSnapshot = AccountSnapshot(accountIndex: accountIndex,
                                              unspentTransactionOutputs: cached,
                                              lastUpdatedAt: .now,
                                              transactionLedger: transactionLedger)
        snapshot.accounts[accountIndex] = accountSnapshot
        try await persistSnapshot()
    }
    
    public func loadLedgerEntry(for transactionHash: Data, accountIndex: UInt32) -> AccountSnapshot.TransactionLedger.Entry? {
        snapshot.accounts[accountIndex]?.transactionLedger.entry(for: transactionHash)
    }
    
    public func insertLedgerEntry(_ entry: AccountSnapshot.TransactionLedger.Entry,
                                  for accountIndex: UInt32) async throws -> Bool {
        var accountSnapshot = snapshot.accounts[accountIndex] ?? AccountSnapshot(accountIndex: accountIndex,
                                                                                 unspentTransactionOutputs: [],
                                                                                 lastUpdatedAt: .now)
        let didInsert = accountSnapshot.transactionLedger.insert(entry)
        guard didInsert else { return false }
        accountSnapshot.lastUpdatedAt = .now
        snapshot.accounts[accountIndex] = accountSnapshot
        try await persistSnapshot()
        return true
    }
    
    public func updateLedgerEntry(_ entry: AccountSnapshot.TransactionLedger.Entry,
                                  for accountIndex: UInt32) async throws -> Bool {
        guard var accountSnapshot = snapshot.accounts[accountIndex] else { return false }
        let didUpdate = accountSnapshot.transactionLedger.update(entry)
        guard didUpdate else { return false }
        accountSnapshot.lastUpdatedAt = .now
        snapshot.accounts[accountIndex] = accountSnapshot
        try await persistSnapshot()
        return true
    }
    
    public func removeLedgerEntries(_ transactionHashes: [Data],
                                    for accountIndex: UInt32) async throws {
        guard !transactionHashes.isEmpty else { return }
        guard var accountSnapshot = snapshot.accounts[accountIndex] else { return }
        var didRemoveEntry = false
        for transactionHash in transactionHashes {
            if accountSnapshot.transactionLedger.removeEntry(for: transactionHash) {
                didRemoveEntry = true
            }
        }
        guard didRemoveEntry else { return }
        accountSnapshot.lastUpdatedAt = .now
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
