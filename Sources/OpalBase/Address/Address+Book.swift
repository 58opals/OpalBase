// Address+Book.swift

import Foundation

extension Address {
    public actor Book {
        struct UsageDerivationCache {
            let baseExtendedPrivateKey: PrivateKey.Extended
            let baseCompressedPublicKey: Data
            let baseFingerprint: Data
        }
        
        private let rootExtendedPrivateKey: PrivateKey.Extended?
        private let rootExtendedPublicKey: PublicKey.Extended
        private let purpose: DerivationPath.Purpose
        private let coinType: DerivationPath.CoinType
        private let account: DerivationPath.Account
        var usageDerivationCache: [DerivationPath.Usage: UsageDerivationCache]
        
        var inventory: Inventory
        var utxoStore: UTXOStore
        var transactionLog: TransactionLog
        
        let gapLimit: Int
        
        let spendReservationExpirationInterval: TimeInterval
        var spendReservationReleaseTasks: [UUID: Task<Void, Never>]
        var spendReservationStates: [UUID: SpendReservation.State]
        
        private let entryPublisher = Entry.Publisher()
        
        init(rootExtendedPrivateKey: PrivateKey.Extended? = nil,
             rootExtendedPublicKey: PublicKey.Extended? = nil,
             purpose: DerivationPath.Purpose,
             coinType: DerivationPath.CoinType,
             account: DerivationPath.Account,
             gapLimit: Int = 20,
             cacheValidityDuration: TimeInterval = 10 * 60,
             spendReservationExpirationInterval: TimeInterval = 10 * 60) async throws {
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
            
            self.inventory = .init(cacheValidityDuration: cacheValidityDuration)
            self.utxoStore = .init()
            self.transactionLog = .init()
            self.spendReservationExpirationInterval = spendReservationExpirationInterval
            self.spendReservationStates = .init()
            self.spendReservationReleaseTasks = .init()
            self.usageDerivationCache = .init()
            
            try buildUsageDerivationCacheIfNeeded()
            try await initializeEntries()
        }
        
        deinit {
            for task in spendReservationReleaseTasks.values {
                task.cancel()
            }
        }
    }
}

extension Address.Book {
    private func buildUsageDerivationCacheIfNeeded() throws {
        guard let rootExtendedPrivateKey else { return }
        
        let accountIndex = try account.deriveHardenedIndex()
        let accountExtendedPrivateKey = try rootExtendedPrivateKey.deriveChildFast(at: [
            purpose.hardenedIndex,
            coinType.hardenedIndex,
            accountIndex
        ])
        let accountCompressedPublicKey = try PublicKey(privateKey: .init(data: accountExtendedPrivateKey.privateKey)).compressedData
        let accountFingerprint = Data(HASH160.hash(accountCompressedPublicKey).prefix(4))
        
        for usage in [DerivationPath.Usage.receiving, .change] {
            let usageExtendedPrivateKey = try accountExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: usage.unhardenedIndex,
                parentCompressedPublicKey: accountCompressedPublicKey,
                parentFingerprint: accountFingerprint
            )
            let usageCompressedPublicKey = try PublicKey(privateKey: .init(data: usageExtendedPrivateKey.privateKey)).compressedData
            let usageFingerprint = Data(HASH160.hash(usageCompressedPublicKey).prefix(4))
            usageDerivationCache[usage] = .init(baseExtendedPrivateKey: usageExtendedPrivateKey,
                                                baseCompressedPublicKey: usageCompressedPublicKey,
                                                baseFingerprint: usageFingerprint)
        }
    }
    
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
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            let childCompressedPublicKey = try PublicKey(privateKey: .init(data: childExtendedPrivateKey.privateKey)).compressedData
            let publicKey = try PublicKey(compressedData: childCompressedPublicKey)
            return try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        }
        
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
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            return try PrivateKey(data: childExtendedPrivateKey.privateKey)
        }
        
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
    func handleIncomingTransaction(_ detailedTransaction: Transaction.Detailed) async throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            
            guard let script = try? Script.decode(lockingScript: lockingScript) else { continue }
            guard let address = try? Address(script: script) else { continue }
            guard inventory.contains(address: address) else { continue }
            
            try await mark(address: address, isUsed: true)
            let utxo = Transaction.Output.Unspent(output: output,
                                                  previousTransactionHash: detailedTransaction.hash,
                                                  previousTransactionOutputIndex: UInt32(index))
            addUTXO(utxo)
        }
    }
    
    func handleOutgoingTransaction(_ transaction: Transaction) {
        for input in transaction.inputs {
            if let utxo = utxoStore.findUTXO(matching: input) {
                removeUTXO(utxo)
            }
        }
    }
}

extension Address.Book {
    func updateCacheValidityDuration(_ newDuration: TimeInterval) {
        inventory.updateCacheValidityDuration(to: newDuration)
    }
}

extension Address.Book {
    func notifyNewEntry(_ entry: Entry) async {
        await entryPublisher.publish(entry)
    }
    
    func observeNewEntries() async -> AsyncStream<Entry> {
        await entryPublisher.observeEntries()
    }
}
