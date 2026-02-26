// AddressModel+BookActor.swift

import Foundation

extension AddressModel {
    public actor BookActor {
        struct UsageDerivationCache {
            let baseExtendedPrivateKey: PrivateKeyModel.ExtendedModel
            let baseCompressedPublicKey: Data
            let baseFingerprint: Data
        }
        
        let rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel?
        let rootExtendedPublicKey: PublicKeyModel.ExtendedModel
        let purpose: DerivationPathModel.PurposeModel
        let coinType: DerivationPathModel.CoinTypeModel
        let account: DerivationPathModel.AccountActor
        var usageDerivationCache: [DerivationPathModel.UsageModel: UsageDerivationCache]
        
        var inventory: InventoryModel
        var utxoStore: UTXORepository
        var transactionLog: TransactionLogModel
        
        let gapLimit: Int
        
        let spendReservationExpirationInterval: TimeInterval
        var spendReservationReleaseTasks: [UUID: Task<Void, Never>]
        var spendReservationStates: [UUID: SpendReservationModel.State]
        
        let entryPublisher = EntryModel.PublisherActor()
        
        init(rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel? = nil,
             rootExtendedPublicKey: PublicKeyModel.ExtendedModel? = nil,
             purpose: DerivationPathModel.PurposeModel,
             coinType: DerivationPathModel.CoinTypeModel,
             account: DerivationPathModel.AccountActor,
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
extension AddressModel.BookActor {
    func readGapLimit() -> Int {
        gapLimit
    }
}
