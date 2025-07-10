// Block+Header+Chain.swift

import Foundation
import BigInt
import SwiftFulcrum

extension Block.Header {
    public actor Chain {
        private let checkpointHeight: UInt32
        private let checkpointHash: Data
        
        private var headers: [UInt32: Block.Header] = .init()
        private var hashes: [UInt32: Data] = .init()
        private var tipHeight: UInt32
        private var tipHash: Data
        
        public init(checkpointHeight: UInt32, checkpointHash: Data) {
            self.checkpointHeight = checkpointHeight
            self.checkpointHash = checkpointHash
            self.tipHeight = checkpointHeight
            self.tipHash = checkpointHash
        }
    }
}

extension Block.Header.Chain {
    public var latestHeight: UInt32 { tipHeight }
    
    public func append(_ header: Block.Header, height: UInt32) throws {
        let headerHash = try verify(header)
        
        if headers.isEmpty && (height == checkpointHeight) {
            guard headerHash == checkpointHash else { throw Error.doesNotConnect(height: height) }
        } else {
            let expectedPreviousBlockHash = tipHash
            guard header.previousBlockHash == expectedPreviousBlockHash else { throw Error.doesNotConnect(height: height) }
        }
        
        headers[height] = header
        hashes[height] = headerHash
        tipHeight = height
        tipHash = headerHash
    }
    
    public func verifyTransaction(hash: Data, merkleProof: [Data], index: Int, height: UInt32) -> Bool {
        guard let header = headers[height] else { return false }
        
        var currentHash = hash
        var currentIndex = index
        for sibling in merkleProof {
            if currentIndex % 2 == 0 {
                currentHash = HASH256.hash(currentHash + sibling)
            } else {
                currentHash = HASH256.hash(sibling + currentHash)
            }
            
            currentIndex >>= 1
        }
        
        return currentHash == header.merkleRoot
    }
    
    public func sync(from startHeight: UInt32? = nil, using fulcrum: Fulcrum) async throws {
        var height = startHeight ?? tipHeight + 1
        var previousBlockHash = tipHash
        while true {
            let response = try await fulcrum.submit(method: .blockchain(.block(.header(height: .init(height), checkpointHeight: nil))),
                                                    responseType: Response.Result.Blockchain.Block.Header.self)
            guard case .single(let id, let result) = response else { break }
            await Log.shared.log("Synced block \(id)")
            
            let headerData = try Data(hexString: result.hex)
            let (header, bytes) = try Block.Header.decode(from: headerData)
            await Log.shared.log("\(bytes) bytes for \(header.encode().hexadecimalString)")
            
            guard header.previousBlockHash == previousBlockHash else { throw Error.doesNotConnect(height: height) }
            let headerHash = try verify(header)
            headers[height] = header
            hashes[height] = headerHash
            previousBlockHash = headerHash
            tipHeight = height
            tipHash = headerHash
            height += 1
        }
    }
}

extension Block.Header.Chain {
    private func getHash(of header: Block.Header) -> Data {
        HASH256.hash(header.encode())
    }
    
    private func getTarget(from bits: UInt32) -> BigUInt {
        let exponent = Int(bits >> 24)
        var mantissa = BigUInt(bits & 0x00ffffff)
        
        if exponent <= 3 {
            mantissa >>= (8 * (3 - exponent))
            return mantissa
        } else {
            return mantissa << (8 * (exponent - 3))
        }
    }
    
    private func verify(_ header: Block.Header) throws -> Data {
        let hash = getHash(of: header)
        let hashNumber = BigUInt(hash.reversedData)
        let target = getTarget(from: header.bits)
        
        guard hashNumber <= target else { throw Error.invalidProofOfWork(height: tipHeight + 1) }
        return hash
    }
}
