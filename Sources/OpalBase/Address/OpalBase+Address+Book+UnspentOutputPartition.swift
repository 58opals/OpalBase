// OpalBase+Address+Book+UnspentOutputPartition.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UnspentOutputPartition: Sendable, Equatable {
        public let bchOnlyUTXOs: Set<OpalBase.Transaction.Output.Unspent>
        public let tokenUTXOs: Set<OpalBase.Transaction.Output.Unspent>
        
        public init(bchOnlyUTXOs: Set<OpalBase.Transaction.Output.Unspent>,
                    tokenUTXOs: Set<OpalBase.Transaction.Output.Unspent>) {
            self.bchOnlyUTXOs = bchOnlyUTXOs
            self.tokenUTXOs = tokenUTXOs
        }
    }
}
