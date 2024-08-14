import Foundation
import SwiftFulcrum

struct Account {
    let extendedKey: PrivateKey.Extended
    let accountIndex: UInt32
    var addressBook: Address.Book
    let fulcrum: Fulcrum
    
    init(extendedKey: PrivateKey.Extended, accountIndex: UInt32) async throws {
        let fulcrum = try Fulcrum()
        
        self.extendedKey = extendedKey
        self.accountIndex = accountIndex
        self.addressBook = try await Address.Book(extendedKey: extendedKey, fulcrum: fulcrum)
        self.fulcrum = fulcrum
    }
}

extension Account {
    func getBalanceFromCache() throws -> Satoshi {
        return try addressBook.getBalanceFromCache()
    }
}
