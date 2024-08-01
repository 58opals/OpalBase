import Foundation

extension Transaction.Output {
    struct Unspent {
        let transactionHash: Data
        let outputIndex: UInt32
        let amount: UInt64
        let lockingScript: Data
    }
}
