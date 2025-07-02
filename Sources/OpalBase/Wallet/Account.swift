// Account.swift

import Foundation
import SwiftFulcrum

public actor Account: Identifiable {
    public let fulcrum: Fulcrum
    
    private let rootExtendedKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    public let id: Data
    
    public var addressBook: Address.Book
    
    init(fulcrumServerURL: String? = nil,
         rootExtendedKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account) async throws {
        self.fulcrum = try Fulcrum(url: fulcrumServerURL)
        
        self.rootExtendedKey = rootExtendedKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        var hashInput: Data = .init()
        hashInput.append(rootExtendedKey.serialize())
        hashInput.append(purpose.hardenedIndex.data)
        hashInput.append(coinType.hardenedIndex.data)
        hashInput.append(try account.getHardenedIndex().data)
        let sha256Hash = SHA256.hash(hashInput)
        self.id = sha256Hash
        
        self.addressBook = try await Address.Book(rootExtendedKey: rootExtendedKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account)
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
