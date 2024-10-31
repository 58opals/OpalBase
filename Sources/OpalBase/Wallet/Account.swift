import Foundation
import SwiftFulcrum

public struct Account {
    let fulcrum: Fulcrum
    
    private let rootExtendedKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
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
        
        self.addressBook = try await Address.Book(rootExtendedKey: rootExtendedKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account)
    }
}

extension Account {
    public func getDerivationPath() -> (DerivationPath.Purpose, DerivationPath.CoinType, DerivationPath.Account) {
        return (purpose, coinType, account)
    }
}

extension Account {
    public func getBalanceFromCache() async throws -> Satoshi {
        return try await addressBook.getTotalBalanceFromCache()
    }
}

/*
#if DEBUG
extension Account {
    internal static func generateDummyAccount(unhardenedAccountIndex: UInt32 = .max) -> Account? {
        Account(unhardenedAccountIndex: unhardenedAccountIndex)
    }
    
    internal init?(unhardenedAccountIndex: UInt32) {
        do {
            guard let dummyAddressBook = Address.Book.generateDummyAddressBook() else { return nil }
            self.fulcrum = try .init()
            self.rootExtendedKey = .init(rootKey: try .init(seed: .init([0x00])))
            self.purpose = .bip44
            self.coinType = .bitcoinCash
            self.account = .init(unhardenedIndex: unhardenedAccountIndex)
            self.addressBook = dummyAddressBook
        } catch {
            print("Dummy account initialization failed: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
*/
