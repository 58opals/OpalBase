// Address+Book+Page.swift

import Foundation

extension Address.Book {
    public struct Page<Transaction> {
        public let transactions: [Transaction]
        public let nextFromHeight: UInt?
    }
}
