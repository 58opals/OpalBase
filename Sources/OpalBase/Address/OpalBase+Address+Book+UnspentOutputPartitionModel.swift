// OpalBase+Address+Book+UnspentOutputPartitionModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UnspentOutputPartitionModel: Sendable, Equatable {
        public let bchOnlyUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>
        public let tokenUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>
        
        public init(bchOnlyUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>,
                    tokenUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>) {
            self.bchOnlyUTXOs = bchOnlyUTXOs
            self.tokenUTXOs = tokenUTXOs
        }
    }
}
