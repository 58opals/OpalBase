import Foundation

extension Wallet {
    func calculateTotalBalance() async throws -> Satoshi {
        var totalBalance: Satoshi = try Satoshi(0)
        for account in accounts {
            let balance = try await account.calculateBalance()
            totalBalance = try totalBalance + balance
        }
        return totalBalance
    }
}
