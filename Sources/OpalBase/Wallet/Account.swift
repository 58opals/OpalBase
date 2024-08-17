import Foundation
import SwiftFulcrum

struct Account {
    let fulcrum: Fulcrum
    
    private let rootExtendedKey: PrivateKey.Extended
    
    private let purpose: DerivationPath.Purpose
    private let coinType: DerivationPath.CoinType
    private let account: DerivationPath.Account
    
    var addressBook: Address.Book
    
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
        
        self.addressBook = try await Address.Book(rootExtendedKey: rootExtendedKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account,
                                                  fulcrum: fulcrum)
    }
}

extension Account {
    func getBalanceFromCache() throws -> Satoshi {
        return try addressBook.getBalanceFromCache()
    }
}
