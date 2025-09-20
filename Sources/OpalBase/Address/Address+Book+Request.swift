// Address+Book+Request.swift

import Foundation

extension Address.Book {
    enum Request: Hashable, Sendable {
        case updateCache
        case updateCacheSubset(Scope)
        case refreshBalances
        case refreshBalancesSubset(Scope)
        case fetchBalance(Address)
        case refreshUTXOSet
        case fetchDetailedTransactions(scope: Scope,
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
        case refreshUsedStatusSubset(Scope)
        case updateAddressUsageStatus
        case updateAddressUsageStatusSubset(Scope)
        case checkIfUsed(Address)
        case scanForUsedAddresses
        
        enum Scope: Hashable, Sendable {
            case receiving
            case change

            init(usage: DerivationPath.Usage) {
                switch usage {
                case .receiving: self = .receiving
                case .change: self = .change
                }
            }
        }
    }
}
