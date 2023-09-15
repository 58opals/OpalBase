// Opal Base by 58 Opals

import Foundation

extension Blockchain {
    struct Block {
        let header: Header
        let transactions: [Transaction]
    }
}

extension Blockchain.Block {
    struct Target {
        let compressed: UInt32
        
        var bits: Data { compressed.data }
        var exponent: UInt8 { bits[0] }
        var significand: Array<UInt8> { Array(bits[1..<4]) }
    }
    
    struct Header {
        let version: UInt32
        let previousBlockHash: Data
        let merkleRoot: Data
        let timestamp: UInt32
        let target: Target
        let nonce: UInt32
    }
}
