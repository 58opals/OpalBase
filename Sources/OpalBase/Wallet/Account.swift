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

extension Account: Identifiable {
    public var id: Int {
        var hasher = Hasher()
        hasher.combine(rootExtendedKey)
        hasher.combine(purpose)
        hasher.combine(coinType)
        hasher.combine(account)
        return hasher.finalize()
    }
}

extension Account: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rootExtendedKey)
        hasher.combine(purpose)
        hasher.combine(coinType)
        hasher.combine(account)
    }

    public static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.rootExtendedKey == rhs.rootExtendedKey &&
        lhs.purpose == rhs.purpose &&
        lhs.coinType == rhs.coinType &&
        lhs.account == rhs.account
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
extension Account {
    static func generateDummyAccount() async -> Account? {
        do {
            let rootExtendedKey = PrivateKey.Extended(rootKey: try .init(seed: .init([0x00])))
            let purpose = DerivationPath.Purpose.bip44
            let coinType = DerivationPath.CoinType.bitcoinCash
            let account = DerivationPath.Account(unhardenedIndex: .max)
            
            return try await .init(rootExtendedKey: rootExtendedKey,
                                   purpose: purpose,
                                   coinType: coinType,
                                   account: account)
        } catch {
            print("Failable initialization failed: \(error.localizedDescription)")
            return nil
        }
    }
}
*/
