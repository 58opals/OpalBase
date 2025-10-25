// PBKDF2.swift

import Foundation
import CryptoKit

struct PBKDF2 {
    enum Error: Swift.Error {
        case invalidParameters
        case keyLengthExceedsLimit
    }
    
    private let symmetricKey: SymmetricKey
    private let saltBytes: Array<UInt8>
    private let iterationCount: Int
    private let blockCount: Int
    private let derivedKeyLength: Int
    private let hmacSHA512: HMAC<SHA512>
    
    private let sha512BlockSize = (512 / 8)
    
    init(password: Array<UInt8>, saltBytes: Array<UInt8>, iterationCount: Int = 4096, derivedKeyLength: Int? = nil) throws {
        precondition(iterationCount > 0)
        let symmetricKey = SymmetricKey(data: password)
        
        let hmacSHA512 = HMAC<SHA512>(key: symmetricKey)
        
        guard iterationCount > 0 && !saltBytes.isEmpty else { throw Error.invalidParameters }
        
        self.derivedKeyLength = derivedKeyLength ?? sha512BlockSize
        let keyLengthFinal = Double(self.derivedKeyLength)
        let hLen = Double(sha512BlockSize)
        if keyLengthFinal > (pow(2, 32) - 1) * hLen { throw Error.keyLengthExceedsLimit }
        
        self.symmetricKey = symmetricKey
        self.saltBytes = saltBytes
        self.iterationCount = iterationCount
        self.hmacSHA512 = hmacSHA512
        
        self.blockCount = Int(ceil(keyLengthFinal / hLen))
    }
    
    func deriveKey() throws -> Data {
        var derivedKey = Array<UInt8>()
        derivedKey.reserveCapacity(self.blockCount * sha512BlockSize)
        for i in 1...self.blockCount {
            if let block = try computeBlock(self.saltBytes, blockNum: i) {
                derivedKey.append(contentsOf: block)
            }
        }
        return Data(Array(derivedKey.prefix(self.derivedKeyLength)))
    }
}

private extension PBKDF2 {
    func makeByteArray(from value: Int) -> Array<UInt8> {
        var byteArray = Array<UInt8>(repeating: 0, count: 4)
        byteArray[0] = UInt8((value >> 24) & 0xff)
        byteArray[1] = UInt8((value >> 16) & 0xff)
        byteArray[2] = UInt8((value >> 8) & 0xff)
        byteArray[3] = UInt8(value & 0xff)
        return byteArray
    }
    
    func computeBlock(_ saltBytes: Array<UInt8>, blockNum: Int) throws -> Array<UInt8>? {
        let u1 = HMAC<SHA512>.authenticationCode(for: saltBytes + makeByteArray(from: blockNum), using: symmetricKey)
        
        var u = u1.bytes
        var blockResult = u.bytes
        if iterationCount > 1 {
            for _ in 2...iterationCount {
                u = HMAC<SHA512>.authenticationCode(for: u, using: symmetricKey).bytes
                for x in 0..<blockResult.count {
                    blockResult[x] = blockResult[x] ^ u[x]
                }
            }
        }
        return blockResult
    }
}
