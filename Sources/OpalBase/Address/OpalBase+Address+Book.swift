// OpalBase+Address+Book.swift

import Foundation

extension _OpalBase.Address {
    public actor Book {
        struct UsageDerivationCache {
            let baseExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel
            let baseCompressedPublicKey: Data
            let baseFingerprint: Data
        }
        
        let rootExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel?
        let rootExtendedPublicKey: OpalBase.PublicKey.ExtendedModel
        let purpose: OpalBase.DerivationPath.PurposeModel
        let coinType: OpalBase.DerivationPath.CoinTypeModel
        let account: OpalBase.DerivationPath.Account
        var usageDerivationCache: [OpalBase.DerivationPath.UsageModel: UsageDerivationCache]
        
        var inventory: InventoryModel
        var utxoStore: UTXORepository
        var transactionLog: TransactionLogModel
        
        let gapLimit: Int
        
        let spendReservationExpirationInterval: TimeInterval
        var spendReservationReleaseTasks: [UUID: Task<Void, Never>]
        var spendReservationStates: [UUID: SpendReservationModel.State]
        
        let entryPublisher = EntryModel.PublisherActor()
        
        init(rootExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel? = nil,
             rootExtendedPublicKey: OpalBase.PublicKey.ExtendedModel? = nil,
             purpose: OpalBase.DerivationPath.PurposeModel,
             coinType: OpalBase.DerivationPath.CoinTypeModel,
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
