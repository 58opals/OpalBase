// Address+Book.swift

import Foundation

extension Address {
    public actor Book {
        private let rootExtendedPrivateKey: PrivateKey.Extended?
        private let rootExtendedPublicKey: PublicKey.Extended
        private let purpose: DerivationPath.Purpose
        private let coinType: DerivationPath.CoinType
        private let account: DerivationPath.Account
        
        var inventory: Inventory
        var unspentTransactionOutputStore: UnspentTransactionOutputStore
        var transactionLog: TransactionLog
        
        let gapLimit: Int
        
        var cacheValidityDuration: TimeInterval
        
        private let entryPublisher = Entry.Publisher()
        
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
            
            self.inventory = .init()
            self.unspentTransactionOutputStore = .init()
            self.transactionLog = .init()
            
            try await initializeEntries()
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
            
            if inventory.contains(address: address) {
                let unspentTransactionOutput = Transaction.Output.Unspent(output: output,
                                                                          previousTransactionHash: detailedTransaction.hash,
                                                                          previousTransactionOutputIndex: UInt32(index))
                addUnspentTransactionOutput(unspentTransactionOutput)
            }
        }
    }
    
    func handleOutgoingTransaction(_ transaction: Transaction) {
        for input in transaction.inputs {
            if let unspentTransactionOutput = unspentTransactionOutputStore.findUnspentTransactionOutput(matching: input) {
                removeUnspentTransactionOutput(unspentTransactionOutput)
            }
        }
    }
}

extension Address.Book {
    func updateCacheValidityDuration(_ newDuration: TimeInterval) {
        cacheValidityDuration = newDuration
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
