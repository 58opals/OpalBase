// AddressModel+BookActor+Request.swift

import Foundation

extension AddressModel.BookActor {
    enum Request: Hashable, Sendable {
        case updateCache(usage: DerivationPathModel.UsageModel? = nil)
        case refreshBalances(usage: DerivationPathModel.UsageModel? = nil)
        case fetchBalance(AddressModel)
        case refreshUTXOSet
        case fetchDetailedTransactions(scope: DerivationPathModel.UsageModel,
                                       fromHeight: UInt?,
                                       toHeight: UInt?,
                                       includeUnconfirmed: Bool)
        case fetchCombinedHistory(fromHeight: UInt?,
                                  toHeight: UInt?,
                                  includeUnconfirmed: Bool)
        case fetchCombinedHistoryPage(fromHeight: UInt?,
                                      window: UInt,
                                      includeUnconfirmed: Bool)
        case refreshUsedStatus(usage: DerivationPathModel.UsageModel? = nil)
        case updateAddressUsageStatus(usage: DerivationPathModel.UsageModel? = nil)
        case checkIfUsed(AddressModel)
        case scanForUsedAddresses
    }
}
