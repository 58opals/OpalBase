// AddressModel+BookActor+EntryModel+Cache.swift

import Foundation

extension AddressModel.BookActor.EntryModel {
    struct Cache {
        var balance: SatoshiModel?
        var lastUpdated: Date?
    }
}

extension AddressModel.BookActor.EntryModel.Cache: Hashable {}

extension AddressModel.BookActor.EntryModel.Cache {
    func checkValidity(currentDate: Date, validityDuration: TimeInterval) -> Bool {
        guard let lastUpdated else { return false }
        guard lastUpdated <= currentDate else { return false }
        return currentDate.timeIntervalSince(lastUpdated) < validityDuration
    }
}
