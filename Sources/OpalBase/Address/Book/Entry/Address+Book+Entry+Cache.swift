// Address+Book+Entry+Cache.swift

import Foundation

extension Address.Book.Entry {
    struct Cache {
        var balance: Satoshi?
        var lastUpdated: Date?
    }
}

extension Address.Book.Entry.Cache: Hashable {}
