// OpalBase+Address+Book+UnspentOutputPartition.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UnspentOutputPartition: Sendable, Equatable {
        let bchOnlyUTXOs: Set<OpalBase.Transaction.Output.Unspent>
        let tokenUTXOs: Set<OpalBase.Transaction.Output.Unspent>
        
        init(bchOnlyUTXOs: Set<OpalBase.Transaction.Output.Unspent>,
                    tokenUTXOs: Set<OpalBase.Transaction.Output.Unspent>) {
            self.bchOnlyUTXOs = bchOnlyUTXOs
            self.tokenUTXOs = tokenUTXOs
        }
    }
}
