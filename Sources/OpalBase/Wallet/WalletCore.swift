// WalletCore.swift

import Foundation

public actor WalletCore {
    public struct SendRequest: Sendable {
        public var inputs: [Transaction.Output.Unspent: PrivateKey]
        public var outputs: [Transaction.Output]
        public var change: Transaction.Output
        public var feePerByte: UInt64
        
        public init(inputs: [Transaction.Output.Unspent: PrivateKey],
                    outputs: [Transaction.Output],
                    change: Transaction.Output,
                    feePerByte: UInt64 = Transaction.defaultFeeRate) {
            self.inputs = inputs
            self.outputs = outputs
            self.change = change
            self.feePerByte = feePerByte
        }
    }
    
    private let repositories: Storage.Facade
    private let gateway: Network.TransactionGateway
    private var isSynced = false
    
    public init(storage: Storage.Facade,
                transactionGateway: Network.TransactionGateway) {
        self.repositories = storage
        self.gateway = transactionGateway
    }
    
    public func sync() async throws {
        guard !isSynced else { return }
        do {
            try await gateway.refreshMempool()
            isSynced = true
        } catch {
            throw Error.syncFailed(error)
        }
    }
    
    public func getBalances(
        for index: UInt32,
        pollInterval: Duration = .seconds(5),
        heartbeat: Duration = .seconds(30)
    ) -> AsyncThrowingStream<Satoshi, Swift.Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [repositories] in
                let clock = ContinuousClock()
                var last: UInt64?
                var lastEmit = clock.now
                while !Task.isCancelled {
                    do {
                        let rows = try await repositories.utxos.forAccount(index)
                        let total = rows.reduce(0) { $0 + $1.value }
                        let now = clock.now
                        if last != total || lastEmit.duration(to: now) >= heartbeat {
                            last = total
                            lastEmit = now
                            continuation.yield(try Satoshi(total))
                        }
                        try await Task.sleep(for: pollInterval)
                    } catch {
                        continuation.finish(throwing: Error.storage(error))
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    public func getUTXOs(
        for index: UInt32,
        pollInterval: Duration = .seconds(5),
        heartbeat: Duration = .seconds(30)
    ) -> AsyncThrowingStream<Set<Transaction.Output.Unspent>, Swift.Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [repositories] in
                let clock = ContinuousClock()
                var last = Set<Transaction.Output.Unspent>()
                var lastEmit = clock.now
                while !Task.isCancelled {
                    do {
                        let rows = try await repositories.utxos.forAccount(index)
                        let current = Set(rows.map { row in
                            Transaction.Output.Unspent(
                                value: row.value,
                                lockingScript: row.lockingScript,
                                previousTransactionHash: .init(naturalOrder: row.txHash),
                                previousTransactionOutputIndex: row.index)
                        })
                        let now = clock.now
                        if current != last || lastEmit.duration(to: now) >= heartbeat {
                            last = current
                            lastEmit = now
                            continuation.yield(current)
                        }
                        try await Task.sleep(for: pollInterval)
                    } catch {
                        continuation.finish(throwing: Error.storage(error))
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    public func send(_ request: SendRequest) async throws -> Transaction.Hash {
        let tx: Transaction
        do {
            tx = try Transaction.createTransaction(
                utxoPrivateKeyPairs: request.inputs,
                recipientOutputs: request.outputs,
                changeOutput: request.change,
                feePerByte: request.feePerByte
            )
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        do {
            return try await gateway.broadcast(tx)
        } catch {
            throw Error.broadcastFailed(error)
        }
    }
}

extension WalletCore {
    public enum Error: Swift.Error, Sendable {
        case syncFailed(Swift.Error)
        case storage(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
    }
}
