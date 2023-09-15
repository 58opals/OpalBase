// Opal Base by 58 Opals

import Foundation

extension Transaction {
    struct Input: Hashable {
        let previousTransactionID: Data
        let outputIndex: UInt32
        let unlockingScript: Data
        let sequenceNumber: UInt32
        
        var scriptSize: VLInt { .init(unlockingScript.count) }
    }
}

extension Transaction.Input: Serializable {
    func serialize() -> Data {
        let raw: Data =
            previousTransactionID +
            outputIndex.data +
            scriptSize.data +
            unlockingScript +
            sequenceNumber.data
        
        return raw
    }
    
    func emptyUnlockingScript() -> Data {
        let emptied: Data =
            previousTransactionID +
            outputIndex.data +
            Data([0]) + // unlocking script is empty!
            sequenceNumber.data
        
        return emptied
    }
}
