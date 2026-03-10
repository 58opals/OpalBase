// OpalBase+Transaction+Cache.swift

import Foundation

extension _OpalBase.Transaction {
    public actor Cache {
        private var store: [OpalBase.Transaction.Hash: (Date, OpalBase.Transaction.Detail)] = .init()
        private let timeToLive: TimeInterval = 600
        
        public init() {}
        
        func loadTransaction(at key: OpalBase.Transaction.Hash) -> OpalBase.Transaction.Detail? {
            if let (time, transaction) = store[key], Date.now.timeIntervalSince(time) < timeToLive { return transaction }
            store[key] = nil
            return nil
        }
        
        func put(_ transaction: OpalBase.Transaction.Detail, at key: OpalBase.Transaction.Hash) {
            store[key] = (.now, transaction)
        }
    }
}
