// Account.swift

import Foundation
import SwiftFulcrum

public actor Account: Identifiable {
    public let fulcrumPool: Wallet.Network.FulcrumPool
    
    private let rootExtendedPrivateKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    public let id: Data
    
    public var addressBook: Address.Book
    
    private var requestQueue: [() async throws -> Void] = .init()
    
    init(fulcrumServerURLs: [String] = [],
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account) async throws {
        self.fulcrumPool = try .init(urls: fulcrumServerURLs)
        
        self.rootExtendedPrivateKey = rootExtendedPrivateKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        var hashInput: Data = .init()
        hashInput.append(rootExtendedPrivateKey.serialize())
        hashInput.append(purpose.hardenedIndex.data)
        hashInput.append(coinType.hardenedIndex.data)
        hashInput.append(try account.getHardenedIndex().data)
        let sha256Hash = SHA256.hash(hashInput)
        self.id = sha256Hash
        
        self.addressBook = try await Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account)
        
        Task { [weak self] in
            guard let self else { return }
            await monitorNetworkStatus()
        }
    }
}

extension Account: Equatable {
    public static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

extension Account {
    public func getRawIndex() -> UInt32 {
        return self.account.unhardenedIndex
    }
    
    public func getUnhardenedIndex() -> UInt32 {
        return self.account.getUnhardenedIndex()
    }
    
    public func getHardenedIndex() throws -> UInt32 {
        return try self.account.getHardenedIndex()
    }
}

extension Account {
    public func getDerivationPath() -> (purpose: DerivationPath.Purpose,
                                        coinType: DerivationPath.CoinType,
                                        account: DerivationPath.Account) {
        return (self.purpose, self.coinType, self.account)
    }
}

extension Account {
    public func getBalanceFromCache() async throws -> Satoshi {
        return try await addressBook.getTotalBalanceFromCache()
    }
}

extension Account {
    func enqueueRequest(_ request: @escaping () async throws -> Void) {
        requestQueue.append(request)
    }
    
    public func processQueuedRequests() async {
        while !requestQueue.isEmpty {
            let request = requestQueue.removeFirst()
            do { try await request() } catch { /* handle/log error if needed */ }
        }
    }
    
    public func observeNetworkStatus() async -> AsyncStream<Wallet.Network.Status> {
        await fulcrumPool.observeStatus()
    }
    
    private func monitorNetworkStatus() async {
        for await status in await fulcrumPool.observeStatus() {
            if status == .online {
                await processQueuedRequests()
                await addressBook.processQueuedRequests()
            }
        }
    }
}
