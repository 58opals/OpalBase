// OpalBase+Address+Book.swift

import Foundation

extension _OpalBase.Address {
    public actor Book {
        struct UsageDerivationCache {
            let baseExtendedPrivateKey: OpalBase.PrivateKey.Extended
            let baseCompressedPublicKey: Data
            let baseFingerprint: Data
        }
        
        let rootExtendedPrivateKey: OpalBase.PrivateKey.Extended?
        let rootExtendedPublicKey: OpalBase.PublicKey.Extended
        let purpose: OpalBase.DerivationPath.Purpose
        let coinType: OpalBase.DerivationPath.CoinType
        let account: OpalBase.DerivationPath.Account
        var usageDerivationCache: [OpalBase.DerivationPath.Usage: UsageDerivationCache]
        
        var inventory: Inventory
        var utxoStore: UTXORepository
        var transactionLog: TransactionLog
        
        let gapLimit: Int
        
        let spendReservationExpirationInterval: TimeInterval
        var spendReservationReleaseTasks: [UUID: Task<Void, Never>]
        var spendReservationStates: [UUID: SpendReservation.State]
        
        let entryPublisher = Entry.PublisherActor()
        
        init(rootExtendedPrivateKey: OpalBase.PrivateKey.Extended? = nil,
             rootExtendedPublicKey: OpalBase.PublicKey.Extended? = nil,
             purpose: OpalBase.DerivationPath.Purpose,
             coinType: OpalBase.DerivationPath.CoinType,
             account: OpalBase.DerivationPath.Account,
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

// MARK: - Gap
extension _OpalBase.Address.Book {
    func readGapLimit() -> Int {
        gapLimit
    }
}
