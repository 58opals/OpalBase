// OpalBase+Address+Book.swift

import Foundation
import OpalCrypto

extension _OpalBase.Address {
    actor Book {
        struct UsageDerivationCache {
            let baseExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate
            let baseCompressedPublicKey: Data
            let baseFingerprint: Data
        }
        
        let rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate?
        let rootExtendedPublicKey: OpalCrypto.Key.ExtendedPublic
        let purpose: OpalBase.Key.DerivationPath.Purpose
        let coinType: OpalBase.Key.DerivationPath.CoinType
        let account: OpalBase.Key.DerivationPath.Account
        var usageDerivationCache: [OpalBase.Key.DerivationPath.Usage: UsageDerivationCache]
        
        var inventory: Inventory
        var utxoStore: UTXORepository
        var transactionLog: TransactionLog
        
        let gapLimit: Int
        
        let spendReservationExpirationInterval: TimeInterval
        var spendReservationReleaseTasks: [UUID: Task<Void, Never>]
        var spendReservationStates: [UUID: SpendReservation.State]
        
        let entryPublisher = Entry.PublisherActor()
        
        init(rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate? = nil,
             rootExtendedPublicKey: OpalCrypto.Key.ExtendedPublic? = nil,
             purpose: OpalBase.Key.DerivationPath.Purpose,
             coinType: OpalBase.Key.DerivationPath.CoinType,
             account: OpalBase.Key.DerivationPath.Account,
             gapLimit: Int = 20,
             cacheValidityDuration: TimeInterval = 10 * 60,
             spendReservationExpirationInterval: TimeInterval = 10 * 60) async throws {
            guard gapLimit > 0 else { throw Error.indexOutOfBounds }

            self.rootExtendedPrivateKey = rootExtendedPrivateKey
            
            if let extendedPrivateKey = rootExtendedPrivateKey {
                self.rootExtendedPublicKey = extendedPrivateKey.publicKey
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
