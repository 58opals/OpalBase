// OpalBase+Address+Book+Entry+Cache.swift

import Foundation

extension _OpalBase.Address.Book.Entry {
    struct Cache {
        var balance: OpalBase.Satoshi?
        var lastUpdated: Date?
    }
}

extension _OpalBase.Address.Book.Entry.Cache: Hashable {}

extension _OpalBase.Address.Book.Entry.Cache {
    func isValid(currentDate: Date, validityDuration: TimeInterval) -> Bool {
        guard let lastUpdated else { return false }
        guard lastUpdated <= currentDate else { return false }
        return currentDate.timeIntervalSince(lastUpdated) < validityDuration
    }
}
