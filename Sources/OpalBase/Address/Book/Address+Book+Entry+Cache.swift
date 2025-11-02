// Address+Book+Entry+Cache.swift

import Foundation

extension Address.Book.Entry {
    struct Cache {
        var balance: Satoshi?
        var lastUpdated: Date?
        var validityDuration: TimeInterval = 10 * 60
        
        var isValid: Bool {
            guard let lastUpdated else { return false }
            return Date().timeIntervalSince(lastUpdated) < validityDuration
        }
    }
}

extension Address.Book.Entry.Cache: Hashable {}
