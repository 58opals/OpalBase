// OpalBase+Transaction+Cache.swift

import Foundation

extension _OpalBase.Transaction {
    public actor Cache {
        private var store: [OpalBase.Transaction.HashModel: (Date, OpalBase.Transaction.DetailedModel)] = .init()
        private let timeToLive: TimeInterval = 600
        
        public init() {}
        
        func loadTransaction(at key: OpalBase.Transaction.HashModel) -> OpalBase.Transaction.DetailedModel? {
            if let (time, transaction) = store[key], Date.now.timeIntervalSince(time) < timeToLive { return transaction }
            store[key] = nil
            return nil
        }
        
        func put(_ transaction: OpalBase.Transaction.DetailedModel, at key: OpalBase.Transaction.HashModel) {
            store[key] = (.now, transaction)
        }
    }
}
