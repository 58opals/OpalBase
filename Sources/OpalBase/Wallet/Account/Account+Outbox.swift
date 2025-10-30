// Account+Outbox.swift

import Foundation

extension Account {
    public actor Outbox {
        private let folderURL: URL
        private let fileManager = FileManager.default
        private var transactionRecords: [Transaction.Hash: Record] = .init()
        private var statusContinuations: [UUID: AsyncStream<StatusUpdate>.Continuation] = .init()
        
        init(folderURL: URL) async throws {
            self.folderURL = folderURL
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try await loadPendingTransactionsFromDisk()
        }
    }
}

private extension Account.Outbox {
    func loadPendingTransactionsFromDisk() async throws {
        transactionRecords.removeAll()
        let urls = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        for url in urls {
            let filename = url.lastPathComponent
            guard let hashData = try? Data(hexString: filename) else { continue }
            let data = try Data(contentsOf: url)
            let hash = Transaction.Hash(naturalOrder: hashData)
            transactionRecords[hash] = Record(transactionData: data,
                                              status: .pending,
                                              attemptCount: 0)
        }
    }
}

extension Account.Outbox {
    func save(transactionData: Data) async throws -> Transaction.Hash {
        let hash = Transaction.Hash(naturalOrder: HASH256.hash(transactionData))
        let url = folderURL.appendingPathComponent(hash.naturalOrder.hexadecimalString)
        transactionRecords[hash] = Record(transactionData: transactionData,
                                          status: .pending,
                                          attemptCount: 0)
        do {
            try transactionData.write(to: url)
        } catch {
            transactionRecords.removeValue(forKey: hash)
            throw error
        }
        emitStatusUpdate(for: hash, status: .pending)
        return hash
    }
    
    func remove(transactionHash: Transaction.Hash) async {
        let url = folderURL.appendingPathComponent(transactionHash.naturalOrder.hexadecimalString)
        try? fileManager.removeItem(at: url)
        if transactionRecords.removeValue(forKey: transactionHash) != nil {
            emitStatusUpdate(for: transactionHash, status: .completed)
        }
    }
    
    func loadPendingTransactions() async -> [Transaction.Hash: Data] {
        transactionRecords.reduce(into: [Transaction.Hash: Data]()) { partialResult, element in
            partialResult[element.key] = element.value.transactionData
        }
    }
    
    func loadEntries() async -> [Transaction.Hash: Entry] {
        transactionRecords.mapValues { record in
            Entry(transactionData: record.transactionData,
                  status: record.status,
                  attemptCount: record.attemptCount)
        }
    }
    
    func loadStatuses() async -> [Transaction.Hash: Status] {
        transactionRecords.mapValues { $0.status }
    }
}

extension Account.Outbox {
    func purgeTransactions() async {
        guard let urls = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for url in urls { try? fileManager.removeItem(at: url) }
        transactionRecords.removeAll()
    }
}

extension Account.Outbox {
    func makeStatusStream() -> AsyncStream<StatusUpdate> {
        AsyncStream { continuation in
            let identifier = UUID()
            
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeStatusContinuation(for: identifier) }
            }
            
            self.registerStatusContinuation(continuation, for: identifier)
        }
    }
    
    func prepareForEnqueue(transactionHash: Transaction.Hash) {
        guard var record = transactionRecords[transactionHash] else { return }
        
        switch record.status {
        case .failed:
            record.status = .pending
            record.attemptCount = 0
            transactionRecords[transactionHash] = record
            emitStatusUpdate(for: transactionHash, status: .pending)
        case .pending, .retrying, .broadcasting, .completed:
            break
        }
    }
    
    func beginBroadcast(for transactionHash: Transaction.Hash) {
        guard var record = transactionRecords[transactionHash] else { return }
        record.attemptCount += 1
        record.status = .broadcasting(attempt: record.attemptCount)
        transactionRecords[transactionHash] = record
        emitStatusUpdate(for: transactionHash, status: record.status)
    }
    
    func recordRetry(for transactionHash: Transaction.Hash, failureDescription: String) {
        guard var record = transactionRecords[transactionHash] else { return }
        let nextAttempt = record.attemptCount + 1
        record.status = .retrying(attempt: nextAttempt, failureDescription: failureDescription)
        transactionRecords[transactionHash] = record
        emitStatusUpdate(for: transactionHash, status: record.status)
    }
    
    func recordFailure(for transactionHash: Transaction.Hash, failureDescription: String) {
        guard var record = transactionRecords[transactionHash] else { return }
        record.status = .failed(failureDescription: failureDescription)
        transactionRecords[transactionHash] = record
        emitStatusUpdate(for: transactionHash, status: record.status)
    }
}

extension Account {
    func purgeOutbox() async {
        await outbox.purgeTransactions()
    }
}

private extension Account.Outbox {
    struct Record: Sendable {
        var transactionData: Data
        var status: Status
        var attemptCount: Int
    }
    
    func registerStatusContinuation(_ continuation: AsyncStream<StatusUpdate>.Continuation,
                                    for identifier: UUID)
    {
        statusContinuations[identifier] = continuation
    }
    
    func removeStatusContinuation(for identifier: UUID) {
        statusContinuations.removeValue(forKey: identifier)
    }
    
    func emitStatusUpdate(for transactionHash: Transaction.Hash, status: Status) {
        guard !statusContinuations.isEmpty else { return }
        let update = StatusUpdate(transactionHash: transactionHash, status: status)
        for continuation in statusContinuations.values {
            continuation.yield(update)
        }
    }
}

extension Account.Outbox {
    struct Entry: Sendable, Equatable {
        public let transactionData: Data
        public let status: Status
        public let attemptCount: Int
        
        public init(transactionData: Data, status: Status, attemptCount: Int) {
            self.transactionData = transactionData
            self.status = status
            self.attemptCount = attemptCount
        }
    }
    
    public enum Status: Sendable, Equatable {
        case pending
        case broadcasting(attempt: Int)
        case retrying(attempt: Int, failureDescription: String)
        case failed(failureDescription: String)
        case completed
    }
    
    public struct StatusUpdate: Sendable, Equatable {
        public let transactionHash: Transaction.Hash
        public let status: Status
        
        public init(transactionHash: Transaction.Hash, status: Status) {
            self.transactionHash = transactionHash
            self.status = status
        }
    }
}

extension Account.Outbox.Status {
    var isEligibleForEnqueue: Bool {
        switch self {
        case .pending, .failed:
            return true
        case .retrying, .broadcasting, .completed:
            return false
        }
    }
}
