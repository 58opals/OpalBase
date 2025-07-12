// Address+Book+Page.swift

import Foundation

extension Address.Book {
    struct Page<Item> {
        let transactions: [Item]
        let nextFromHeight: UInt?
    }
}
