import Foundation

extension Wallet {
    func calculateBalance() throws -> Satoshi {
        var totalBalance: UInt64 = 0
        
        for account in self.accounts {
            totalBalance += try account.getBalanceFromCache().uint64
        }
        
        return try Satoshi(totalBalance)
    }
}
