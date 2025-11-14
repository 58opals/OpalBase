// Address+Book+Request.swift

import Foundation

extension Address.Book {
    public enum Request: Hashable, Sendable {
        case updateCache(usage: DerivationPath.Usage? = nil)
        case refreshBalances(usage: DerivationPath.Usage? = nil)
        case fetchBalance(Address)
        case refreshUTXOSet
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
        case refreshUsedStatus(usage: DerivationPath.Usage? = nil)
        case updateAddressUsageStatus(usage: DerivationPath.Usage? = nil)
        case checkIfUsed(Address)
        case scanForUsedAddresses
    }
}
