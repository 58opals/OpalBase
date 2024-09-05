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
                account: DerivationPath.Account,
                fetchBalance: Bool = true) async throws {
        self.fulcrum = try Fulcrum(url: fulcrumServerURL)
        
        self.rootExtendedKey = rootExtendedKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        self.addressBook = try await Address.Book(rootExtendedKey: rootExtendedKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account,
                                                  fetchBalance: fetchBalance,
                                                  fulcrum: fulcrum)
    }
}

extension Account {
    public func getDerivationPath() -> (DerivationPath.Purpose, DerivationPath.CoinType, DerivationPath.Account) {
        return (purpose, coinType, account)
    }
}

extension Account {
    public func getBalanceFromCache() throws -> Satoshi {
        return try addressBook.getBalanceFromCache()
    }
}

extension Account {
    public static func generateDummyAccount(unhardenedAccountIndex: UInt32 = .max) -> Account? {
        Account(unhardenedAccountIndex: unhardenedAccountIndex)
    }
    
    private init?(unhardenedAccountIndex: UInt32) {
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

/*
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
*/
