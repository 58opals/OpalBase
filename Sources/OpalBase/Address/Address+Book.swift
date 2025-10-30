// Address+Book.swift

import Foundation

extension Address {
    public actor Book {
        private let rootExtendedPrivateKey: PrivateKey.Extended?
        private let rootExtendedPublicKey: PublicKey.Extended
        private let purpose: DerivationPath.Purpose
        private let coinType: DerivationPath.CoinType
        private let account: DerivationPath.Account
        
        var derivationPathToAddress: [DerivationPath: Address] = .init()
        
        var receivingEntries: [Entry] = .init()
        var changeEntries: [Entry] = .init()
        
        var addressToEntry: [Address: Entry] = .init()
        
        var utxos: Set<Transaction.Output.Unspent> = .init()
        
        var transactionHistories: [Transaction.Hash: History.Transaction.Record] = .init()
        var scriptHashToTransactions: [String: Set<Transaction.Hash>] = .init()
        
        let gapLimit: Int
        let maxIndex = UInt32.max
        
        var cacheValidityDuration: TimeInterval
        
        private let requestRouter = RequestRouter<Request>()
        var entryContinuations: [UUID: AsyncStream<Entry>.Continuation] = .init()
        
        init(rootExtendedPrivateKey: PrivateKey.Extended? = nil,
             rootExtendedPublicKey: PublicKey.Extended? = nil,
             purpose: DerivationPath.Purpose,
             coinType: DerivationPath.CoinType,
             account: DerivationPath.Account,
             gapLimit: Int = 20,
             cacheValidityDuration: TimeInterval = 10 * 60) async throws {
            self.rootExtendedPrivateKey = rootExtendedPrivateKey
            
            if let extendedPrivateKey = rootExtendedPrivateKey {
                self.rootExtendedPublicKey = try .init(extendedPrivateKey: extendedPrivateKey)
            } else if let extendedPublicKey = rootExtendedPublicKey {
                self.rootExtendedPublicKey = extendedPublicKey
            } else {
                throw Error.privateKeyNotFound
            }
            
            self.purpose = purpose
            self.coinType = coinType
            self.account = account
            
            self.gapLimit = gapLimit
            
            self.cacheValidityDuration = cacheValidityDuration
            
            try initializeEntries()
            
            for entry in receivingEntries + changeEntries {
                addressToEntry[entry.address] = entry
                derivationPathToAddress[entry.derivationPath] = entry.address
            }
        }
    }
}

extension Address.Book {
    func enqueueRequest(for request: Request,
                        priority: TaskPriority? = nil,
                        retryPolicy: RequestRouter<Request>.RetryPolicy = .retry,
                        operation: @escaping @Sendable () async throws -> Void) async {
        let handle = await requestRouter.handle(for: request)
        _ = await handle.enqueue(priority: priority, retryPolicy: retryPolicy, operation: operation)
    }
    
    func processQueuedRequests() async {
        await requestRouter.resume()
    }
    
    func suspendQueuedRequests() async {
        await requestRouter.suspend()
    }
    
    func resumeQueuedRequests() async {
        await requestRouter.resume()
    }
    
    func executeOrEnqueue(_ request: Request,
                          priority: TaskPriority? = nil,
                          operation: @escaping @Sendable () async throws -> Void) async throws {
        do { try await operation() }
        catch {
            await enqueueRequest(for: request,
                                 priority: priority,
                                 operation: operation)
            throw error
        }
    }
    
    func executeOrEnqueue<T: Sendable>(_ request: Request,
                                       priority: TaskPriority? = nil,
                                       operation: @escaping @Sendable () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch {
            await enqueueRequest(for: request,
                                 priority: priority) {
                _ = try await operation()
            }
            throw error
        }
    }
}

extension Address.Book {
    func createDerivationPath(usage: DerivationPath.Usage,
                              index: UInt32) throws -> DerivationPath {
        let derivationPath = try DerivationPath(purpose: self.purpose,
                                                coinType: self.coinType,
                                                account: self.account,
                                                usage: usage,
                                                index: index)
        return derivationPath
    }
    
    func generateAddress(at index: UInt32, for usage: DerivationPath.Usage) throws -> Address {
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        let derivedPublicKey: PublicKey.Extended
        if let extendedPrivateKey = rootExtendedPrivateKey {
            derivedPublicKey = try extendedPrivateKey.deriveChildPublicKey(at: derivationPath)
        } else {
            derivedPublicKey = try rootExtendedPublicKey.deriveChild(at: derivationPath)
        }
        
        let publicKey = try PublicKey(compressedData: derivedPublicKey.publicKey)
        let address = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        
        return address
    }
    
    func generatePrivateKey(at index: UInt32, for usage: DerivationPath.Usage) throws -> PrivateKey {
        guard let extendedPrivateKey = rootExtendedPrivateKey else { throw Error.privateKeyNotFound }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        let privateKey = try PrivateKey(data: extendedPrivateKey.deriveChild(at: derivationPath).privateKey)
        
        return privateKey
    }
}

// MARK: - Gap
extension Address.Book {
    func readGapLimit() -> Int {
        gapLimit
    }
}

// MARK: - Transaction
extension Address.Book {
    func handleIncomingTransaction(_ detailedTransaction: Transaction.Detailed) throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            let address = try Address(script: .decode(lockingScript: lockingScript))
            
            if derivationPathToAddress.values.contains(address) {
                let utxo = Transaction.Output.Unspent(output: output,
                                                      previousTransactionHash: detailedTransaction.hash,
                                                      previousTransactionOutputIndex: UInt32(index))
                addUTXO(utxo)
            }
        }
    }
    
    func handleOutgoingTransaction(_ transaction: Transaction) {
        for input in transaction.inputs {
            if let utxo = utxos.first(
                where: {
                    $0.previousTransactionHash == input.previousTransactionHash && $0.previousTransactionOutputIndex == input.previousTransactionOutputIndex
                }
            ) {
                removeUTXO(utxo)
            }
        }
    }
}

extension Address.Book {
    func updateCacheValidityDuration(_ newDuration: TimeInterval) {
        cacheValidityDuration = newDuration
        
        for index in receivingEntries.indices {
            receivingEntries[index].cache.validityDuration = newDuration
            addressToEntry[receivingEntries[index].address] = receivingEntries[index]
        }
        
        for index in changeEntries.indices {
            changeEntries[index].cache.validityDuration = newDuration
            addressToEntry[changeEntries[index].address] = changeEntries[index]
        }
    }
}

extension Address.Book {
    private func addEntryContinuation(_ continuation: AsyncStream<Entry>.Continuation) -> UUID {
        let identifier = UUID()
        entryContinuations[identifier] = continuation
        return identifier
    }
    
    private func removeEntryContinuation(_ identifier: UUID) {
        entryContinuations.removeValue(forKey: identifier)
    }
    
    func notifyNewEntry(_ entry: Entry) {
        for continuation in entryContinuations.values { continuation.yield(entry) }
    }
    
    func observeNewEntries() -> AsyncStream<Entry> {
        AsyncStream { continuation in
            let identifier = addEntryContinuation(continuation)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeEntryContinuation(identifier) }
            }
        }
    }
}
