// Address+Book+Page.swift

import Foundation

extension Address.Book {
    public struct Page<Item: Sendable> {
        public let transactions: [Item]
        public let nextStartingHeight: UInt?
    }
}

extension Address.Book.Page: Sendable {}
