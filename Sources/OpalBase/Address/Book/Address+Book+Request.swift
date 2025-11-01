// Address+Book+Request.swift

import Foundation

extension Address.Book {
    public enum Request: Hashable, Sendable {
        case updateCache
        case updateCacheSubset(DerivationPath.Usage)
        case refreshBalances
        case refreshBalancesSubset(DerivationPath.Usage)
        case fetchBalance(Address)
        case refreshUnspentTransactionOutputSet
        case fetchDetailedTransactions(scope: DerivationPath.Usage,
                                       fromHeight: UInt?,
                                       toHeight: UInt?,
                                       includeUnconfirmed: Bool)
        case fetchCombinedHistory(fromHeight: UInt?,
                                  toHeight: UInt?,
                                  includeUnconfirmed: Bool)
        case fetchCombinedHistoryPage(fromHeight: UInt?,
                                      window: UInt,
                                      includeUnconfirmed: Bool)
        case refreshUsedStatus
        case refreshUsedStatusSubset(DerivationPath.Usage)
        case updateAddressUsageStatus
        case updateAddressUsageStatusSubset(DerivationPath.Usage)
        case checkIfUsed(Address)
        case scanForUsedAddresses
    }
}
