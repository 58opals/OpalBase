import Foundation
import SwiftFulcrum

public struct Account {
    let fulcrum: Fulcrum
    
    private let rootExtendedKey: PrivateKey.Extended
    
    private let purpose: DerivationPath.Purpose
    private let coinType: DerivationPath.CoinType
    private let account: DerivationPath.Account
    
    public var addressBook: Address.Book
    
    public init(fulcrumServerURL: String? = nil,
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
    public func getBalanceFromCache() throws -> Satoshi {
        return try addressBook.getBalanceFromCache()
    }
}

#if DEBUG
extension Account {
    public init(unhardenedAccountIndex: UInt32) {
        self.fulcrum = try! .init()
        self.rootExtendedKey = .init(rootKey: try! .init(seed: (0...100).randomElement()!.data))
        self.purpose = .bip44
        self.coinType = .bitcoinCash
        self.account = .init(unhardenedIndex: unhardenedAccountIndex)
        self.addressBook = Address.Book(unhardenedAccountIndex: unhardenedAccountIndex)
    }
}
#endif
