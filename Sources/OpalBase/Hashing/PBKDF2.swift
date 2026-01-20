// PBKDF2.swift

import Foundation
import CryptoKit

struct PBKDF2 {
    enum Error: Swift.Error {
        case invalidParameters
        case keyLengthExceedsLimit
    }
    
    private let symmetricKey: SymmetricKey
    private let salt: Data
    private let iterationCount: Int
    private let blockCount: Int
    private let derivedKeyLength: Int
    
    private let sha512BlockSize = (512 / 8)
    
    init(password: Data, salt: Data, iterationCount: Int = 4096, derivedKeyLength: Int? = nil) throws {
        precondition(iterationCount > 0)
        let symmetricKey = SymmetricKey(data: password)
        
        guard iterationCount > 0 && !salt.isEmpty else { throw Error.invalidParameters }
        
        
        self.derivedKeyLength = derivedKeyLength ?? sha512BlockSize
        let keyLengthFinal = Double(self.derivedKeyLength)
        let hLen = Double(sha512BlockSize)
        if keyLengthFinal > (pow(2, 32) - 1) * hLen { throw Error.keyLengthExceedsLimit }
        
        self.symmetricKey = symmetricKey
        self.salt = salt
        self.iterationCount = iterationCount
        self.blockCount = Int(ceil(keyLengthFinal / hLen))
    }
    
    func deriveKey() throws -> Data {
        var derivedKey = Array<UInt8>(repeating: 0, count: self.blockCount * sha512BlockSize)
        var derivedKeyIndex = 0
        for blockIndex in 1...self.blockCount {
            let block = try computeBlock(self.salt, blockNumber: blockIndex)
            let endIndex = derivedKeyIndex + block.count
            derivedKey.replaceSubrange(derivedKeyIndex..<endIndex, with: block)
            derivedKeyIndex = endIndex
        }
        return Data(Array(derivedKey.prefix(self.derivedKeyLength)))
    }
}

private extension PBKDF2 {
    func makeBlockNumberBytes(from value: Int) -> Array<UInt8> {
        var blockNumberBytes = Array<UInt8>(repeating: 0, count: 4)
        blockNumberBytes[0] = UInt8((value >> 24) & 0xff)
        blockNumberBytes[1] = UInt8((value >> 16) & 0xff)
        blockNumberBytes[2] = UInt8((value >> 8) & 0xff)
        blockNumberBytes[3] = UInt8(value & 0xff)
        return blockNumberBytes
    }
    
    func computeBlock(_ salt: Data, blockNumber: Int) throws -> Array<UInt8> {
        var blockInput = Data()
        blockInput.reserveCapacity(salt.count + 4)
        blockInput.append(salt)
        blockInput.append(contentsOf: makeBlockNumberBytes(from: blockNumber))
        
        let firstAuthenticationCode = HMAC<SHA512>.authenticationCode(for: blockInput, using: symmetricKey)
        
        var currentBlock = Array<UInt8>(repeating: 0, count: sha512BlockSize)
        var blockResult = Array<UInt8>(repeating: 0, count: sha512BlockSize)
        
        firstAuthenticationCode.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            guard bytes.count == sha512BlockSize, let bytesAddress = bytes.baseAddress else {
                return
            }
            currentBlock.withUnsafeMutableBufferPointer { currentBuffer in
                currentBuffer.baseAddress?.update(from: bytesAddress, count: sha512BlockSize)
            }
            blockResult.withUnsafeMutableBufferPointer { resultBuffer in
                resultBuffer.baseAddress?.update(from: bytesAddress, count: sha512BlockSize)
            }
        }
        
        if iterationCount > 1 {
            for _ in 2...iterationCount {
                let authenticationCode = HMAC<SHA512>.authenticationCode(for: currentBlock, using: symmetricKey)
                authenticationCode.withUnsafeBytes { buffer in
                    let bytes = buffer.bindMemory(to: UInt8.self)
                    for index in 0..<sha512BlockSize {
                        let value = bytes[index]
                        currentBlock[index] = value
                        blockResult[index] ^= value
                    }
                }
            }
        }
        
        return blockResult
    }
}
