// Address+Book+Page.swift

import Foundation

extension Address.Book {
    public struct Page<Item> {
        public let transactions: [Item]
        public let nextFromHeight: UInt?
    }
}
