import Foundation
import SwiftFulcrum

extension Address.Book {
    public func refreshUTXOSet(fulcrum: Fulcrum) async throws {
        var updatedUTXOs = [Transaction.Output.Unspent]()
        
        for entry in (receivingEntries + changeEntries) {
            let newUTXOs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
            let newUTXOsWithTheCorrectlyOrderedPreviousTransactionHash = newUTXOs.map {
                Transaction.Output.Unspent(value: $0.value,
                                           lockingScript: $0.lockingScript,
                                           previousTransactionHash: $0.previousTransactionHash,
                                           previousTransactionOutputIndex: $0.previousTransactionOutputIndex)
            }
            updatedUTXOs.append(contentsOf: newUTXOsWithTheCorrectlyOrderedPreviousTransactionHash)
        }
        
        clearUTXOs()
        addUTXOs(updatedUTXOs)
    }
}
