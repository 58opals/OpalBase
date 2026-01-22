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
            var writer = Data.Writer()
            writer.reserveCapacity(80)
            writer.writeLittleEndian(version)
            writer.writeData(previousBlockHash)
            writer.writeData(merkleRoot)
            writer.writeLittleEndian(time)
            writer.writeLittleEndian(bits)
            writer.writeLittleEndian(nonce)
            return writer.data
        }
        
        static func decode(from data: Data) throws -> (blockHeader: Header, bytesRead: Int) {
            var reader = Data.Reader(data)
            let blockHeader = try decode(from: &reader)
            return (blockHeader, reader.bytesRead)
        }
        
        static func decode(from reader: inout Data.Reader) throws -> Header {
            let version: Int32 = try reader.readLittleEndian()
            let previousBlockHash = try reader.readData(count: 32)
            let merkleRoot = try reader.readData(count: 32)
            let time: UInt32 = try reader.readLittleEndian()
            let bits: UInt32 = try reader.readLittleEndian()
            let nonce: UInt32 = try reader.readLittleEndian()
            return Header(version: version,
                          previousBlockHash: previousBlockHash,
                          merkleRoot: merkleRoot,
                          time: time,
                          bits: bits,
                          nonce: nonce)
        }
    }
}

extension Block.Header: Sendable {}
extension Block.Header: Equatable {}

extension Block.Header {
    var proofOfWorkHash: Data { return HASH256.hash(encode()).reversedData }
    
    public static func calculateTarget(for bits: UInt32) -> LargeUnsignedInteger {
        let exponent = Int(bits >> 24)
        var mantissa = LargeUnsignedInteger(UInt64(bits & 0x00ff_ffff))
        
        if exponent <= 3 {
            mantissa = mantissa.shiftRight(by: 8 * (3 - exponent))
            return mantissa
        } else {
            return mantissa.shiftLeft(by: 8 * (exponent - 3))
        }
    }
    
    public var isProofOfWorkSatisfied: Bool {
        let hashNumber = LargeUnsignedInteger(proofOfWorkHash)
        let target = Block.Header.calculateTarget(for: bits)
        return hashNumber <= target
    }
}
