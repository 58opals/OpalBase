// OpalBase+Address+Book+EntryModel+Cache.swift

import Foundation

extension _OpalBase.Address.Book.EntryModel {
    struct Cache {
        var balance: OpalBase.Satoshi?
        var lastUpdated: Date?
    }
}

extension _OpalBase.Address.Book.EntryModel.Cache: Hashable {}

extension _OpalBase.Address.Book.EntryModel.Cache {
    func checkValidity(currentDate: Date, validityDuration: TimeInterval) -> Bool {
        guard let lastUpdated else { return false }
        guard lastUpdated <= currentDate else { return false }
        return currentDate.timeIntervalSince(lastUpdated) < validityDuration
    }
}
