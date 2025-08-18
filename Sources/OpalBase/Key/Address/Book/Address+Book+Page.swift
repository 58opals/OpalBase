// Address+Book+Page.swift

import Foundation

extension Address.Book {
    public struct Page<Item: Sendable> {
        let transactions: [Item]
        let nextFromHeight: UInt?
    }
}

extension Address.Book.Page: Sendable {}
