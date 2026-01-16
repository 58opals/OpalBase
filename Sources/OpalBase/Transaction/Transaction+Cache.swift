// Transaction+Cache.swift

import Foundation

extension Transaction {
    public actor Cache {
        static let shared = Cache()
        private var store: [Transaction.Hash: (Date, Transaction.Detailed)] = .init()
        private let timeToLive: TimeInterval = 600
        
        func loadTransaction(at key: Transaction.Hash) -> Transaction.Detailed? {
            if let (time, transaction) = store[key], Date().timeIntervalSince(time) < timeToLive { return transaction }
            store[key] = nil
            return nil
        }
        
        func put(_ transaction: Transaction.Detailed, at key: Transaction.Hash) {
            store[key] = (.now, transaction)
        }
    }
}
