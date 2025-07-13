// Address+Book+Page.swift

import Foundation

extension Address.Book {
    public struct Page<Item> {
        let transactions: [Item]
        let nextFromHeight: UInt?
    }
}
