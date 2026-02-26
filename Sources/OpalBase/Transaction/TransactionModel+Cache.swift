// TransactionModel+Cache.swift

import Foundation

extension TransactionModel {
    public actor Cache {
        private var store: [TransactionModel.HashModel: (Date, TransactionModel.DetailedModel)] = .init()
        private let timeToLive: TimeInterval = 600
        
        public init() {}
        
        func loadTransaction(at key: TransactionModel.HashModel) -> TransactionModel.DetailedModel? {
            if let (time, transaction) = store[key], Date.now.timeIntervalSince(time) < timeToLive { return transaction }
            store[key] = nil
            return nil
        }
        
        func put(_ transaction: TransactionModel.DetailedModel, at key: TransactionModel.HashModel) {
            store[key] = (.now, transaction)
        }
    }
}
