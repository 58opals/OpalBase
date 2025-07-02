// Block+Header.swift

import Foundation

extension Block {
    struct Header {
        let version: Int32
        let previousBlockHash: Data
        let merkleRoot: Data
        let time: UInt32
        let bits: UInt32
        let nonce: UInt32
        
        func encode() -> Data {
            var data = Data()
            data.append(contentsOf: withUnsafeBytes(of: version.littleEndian, Array.init))
            data.append(previousBlockHash)
            data.append(merkleRoot)
            data.append(contentsOf: withUnsafeBytes(of: time.littleEndian, Array.init))
            data.append(contentsOf: withUnsafeBytes(of: bits.littleEndian, Array.init))
            data.append(contentsOf: withUnsafeBytes(of: nonce.littleEndian, Array.init))
            return data
        }
        
        static func decode(from data: Data) throws -> (blockHeader: Header, bytesRead: Int) {
            var index = data.startIndex
            let (version, newIndex1): (Int32, Data.Index) = data.extractValue(from: index)
            index = newIndex1
            let previousBlockHash = data[index..<index + 32]
            index += 32
            let merkleRoot = data[index..<index + 32]
            index += 32
            let (time, newIndex2): (UInt32, Data.Index) = data.extractValue(from: index)
            index = newIndex2
            let (bits, newIndex3): (UInt32, Data.Index) = data.extractValue(from: index)
            index = newIndex3
            let (nonce, newIndex4): (UInt32, Data.Index) = data.extractValue(from: index)
            index = newIndex4
            let blockHeader = Header(version: version, previousBlockHash: previousBlockHash, merkleRoot: merkleRoot, time: time, bits: bits, nonce: nonce)
            return (blockHeader, index - data.startIndex)
        }
    }
}
