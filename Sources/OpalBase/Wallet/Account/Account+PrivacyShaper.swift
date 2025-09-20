// Account+PrivacyShaper.swift

import Foundation

extension Account {
    public actor PrivacyShaper {
        private struct AnyOperation: Sendable {
            let execute: @Sendable () async -> Void
        }
        
        private let configuration: Configuration
        private var pendingOperations: [UUID: AnyOperation] = .init()
        private var batchingTask: Task<Void, Never>?
        private var generator = SystemRandomNumberGenerator()
        
        init(configuration: Configuration) {
            self.configuration = configuration
        }
        
        deinit {
            batchingTask?.cancel()
        }
    }
}

extension Account.PrivacyShaper {
    var nextDecoyCount: Int {
        guard configuration.decoyProbability > 0 else { return 0 }
        let draw = Double.random(in: 0.0 ... 1.0, using: &generator)
        guard draw <= configuration.decoyProbability else { return 0 }
        
        if configuration.decoyQueryRange.lowerBound == configuration.decoyQueryRange.upperBound {
            return configuration.decoyQueryRange.lowerBound
        }
        
        return Int.random(in: configuration.decoyQueryRange, using: &generator)
    }
    
    func scheduleSensitiveOperation<Result: Sendable>(
        decoys: [@Sendable () async -> Void] = .init(),
        operation: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        
        try await withCheckedThrowingContinuation { continuation in
            let identifier = UUID()
            pendingOperations[identifier] = AnyOperation {
                await self.performWithJitter {
                    do {
                        let value = try await operation()
                        continuation.resume(returning: value)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            enqueueDecoys(decoys)
            scheduleBatchIfNeeded()
        }
    }
    
    func applyCoinSelectionHeuristics(to utxos: [Transaction.Output.Unspent]) -> [Transaction.Output.Unspent] {
        guard configuration.randomizeUTXOOrdering, utxos.count > 1 else { return utxos }
        return utxos.shuffled(using: &generator)
    }
    
    func randomizeOutputs(_ outputs: [Transaction.Output]) -> [Transaction.Output] {
        guard configuration.randomizeRecipientOrdering, outputs.count > 1 else { return outputs }
        return outputs.shuffled(using: &generator)
    }
    
    private func enqueueDecoys(_ decoys: [@Sendable () async -> Void]) {
        guard !decoys.isEmpty else { return }
        for decoy in decoys {
            let identifier = UUID()
            pendingOperations[identifier] = AnyOperation {
                await self.performWithJitter {
                    await decoy()
                }
            }
        }
    }
    
    private func scheduleBatchIfNeeded() {
        guard !pendingOperations.isEmpty else { return }
        guard batchingTask == nil else { return }
        let configuration = self.configuration
        let delay = randomNanoseconds(in: configuration.batchingIntervalRange)
        batchingTask = Task {
            await self.sleep(nanoseconds: delay)
            await self.flushPending()
        }
    }
    
    private func flushPending() async {
        let operations = Array(pendingOperations.values)
        pendingOperations.removeAll()
        batchingTask = nil
        
        var shuffled = operations
        shuffled.shuffle(using: &generator)
        for operation in shuffled {
            await operation.execute()
        }
    }
    
    private func performWithJitter(_ operation: @escaping @Sendable () async -> Void) async {
        let delay = randomNanoseconds(in: configuration.operationJitterRange)
        await sleep(nanoseconds: delay)
        await operation()
    }
    
    private func sleep(nanoseconds: UInt64) async {
        guard nanoseconds > 0 else { return }
        do { try await Task.sleep(nanoseconds: nanoseconds) }
        catch { }
    }
    
    private func randomNanoseconds(in range: ClosedRange<UInt64>) -> UInt64 {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        return UInt64.random(in: range, using: &generator)
    }
}
