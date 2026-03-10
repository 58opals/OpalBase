// OpalBase+Address+Book+Request.swift

import Foundation

extension _OpalBase.Address.Book {
    enum Request: Hashable, Sendable {
        case updateCache(usage: OpalBase.Key.DerivationPath.Usage? = nil)
        case refreshBalances(usage: OpalBase.Key.DerivationPath.Usage? = nil)
        case fetchBalance(OpalBase.Address)
        case refreshUTXOSet
        case fetchDetailedTransactions(scope: OpalBase.Key.DerivationPath.Usage,
                                       fromHeight: UInt?,
                                       toHeight: UInt?,
                                       includeUnconfirmed: Bool)
        case fetchCombinedHistory(fromHeight: UInt?,
                                  toHeight: UInt?,
                                  includeUnconfirmed: Bool)
        case fetchCombinedHistoryPage(fromHeight: UInt?,
                                      window: UInt,
                                      includeUnconfirmed: Bool)
        case refreshUsedStatus(usage: OpalBase.Key.DerivationPath.Usage? = nil)
        case updateAddressUsageStatus(usage: OpalBase.Key.DerivationPath.Usage? = nil)
        case checkIfUsed(OpalBase.Address)
        case scanForUsedAddresses
    }
}
