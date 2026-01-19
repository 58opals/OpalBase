// Block+Header.swift

import Foundation

extension Block {
    public struct Header {
        public let version: Int32
        public let previousBlockHash: Data
        public let merkleRoot: Data
        public let time: UInt32
        public let bits: UInt32
        public let nonce: UInt32
        
        public init(version: Int32,
                    previousBlockHash: Data,
                    merkleRoot: Data,
                    time: UInt32,
                    bits: UInt32,
                    nonce: UInt32) {
            self.version = version
            self.previousBlockHash = previousBlockHash
            self.merkleRoot = merkleRoot
            self.time = time
            self.bits = bits
            self.nonce = nonce
        }
        
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
            let (version, newIndex1): (Int32, Data.Index) = try data.extractValue(from: index)
            index = newIndex1
            guard index + 32 <= data.endIndex else { throw Data.Error.indexOutOfRange }
            let previousBlockHash = data[index..<index + 32]
            index += 32
            guard index + 32 <= data.endIndex else { throw Data.Error.indexOutOfRange }
            let merkleRoot = data[index..<index + 32]
            index += 32
            let (time, newIndex2): (UInt32, Data.Index) = try data.extractValue(from: index)
            index = newIndex2
            let (bits, newIndex3): (UInt32, Data.Index) = try data.extractValue(from: index)
            index = newIndex3
            let (nonce, newIndex4): (UInt32, Data.Index) = try data.extractValue(from: index)
            index = newIndex4
            let blockHeader = Header(version: version, previousBlockHash: previousBlockHash, merkleRoot: merkleRoot, time: time, bits: bits, nonce: nonce)
            return (blockHeader, index - data.startIndex)
        }
    }
}

extension Block.Header: Sendable {}
extension Block.Header: Equatable {}

extension Block.Header {
    var proofOfWorkHash: Data { return HASH256.hash(encode()).reversedData }
    
    public static func calculateTarget(for bits: UInt32) -> BigUInt {
        let exponent = Int(bits >> 24)
        var mantissa = BigUInt(bits & 0x00ff_ffff)
        
        if exponent <= 3 {
            mantissa >>= (8 * (3 - exponent))
            return mantissa
        } else {
            return mantissa << (8 * (exponent - 3))
        }
    }
    
    public var isProofOfWorkSatisfied: Bool {
        let hash = proofOfWorkHash
        let hashNumber = BigUInt(hash.reversedData)
        let target = Block.Header.calculateTarget(for: bits)
        return hashNumber <= target
    }
}
