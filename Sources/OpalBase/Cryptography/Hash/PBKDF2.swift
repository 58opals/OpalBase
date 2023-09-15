// Opal Base by 58 Opals

import Foundation
import CryptoKit

struct CSDigest {
    public static func sha512(_ bytes: Array<UInt8>) -> Array<UInt8> {
        return Array<UInt8>(SHA512.hash(data: bytes))
    }
}

final class CSHMAC {
    public enum Error: Swift.Error {
        case authenticateError
        case invalidInput
    }
    
    enum Variant {
        case sha1, sha256, sha384, sha512, md5
        
        var digestLength: Int {
            switch self {
            case .sha512:
                return 512 / 8
            default:
                fatalError()
            }
        }
        
        func calculateHash(_ bytes: Array<UInt8>) -> Array<UInt8> {
            switch self {
            case .sha512:
                return CSDigest.sha512(bytes)
            default:
                fatalError()
            }
        }
        
        func blockSize() -> Int {
            switch self {
            case .sha512:
                return 128
            default:
                fatalError()
            }
        }
    }
    
    var key: Array<UInt8>
    let variant: Variant
    
    public init(key: Array<UInt8>, variant: CSHMAC.Variant = .sha512) {
        self.variant = variant
        self.key = key
        
        if key.count > variant.blockSize() {
            let hash = variant.calculateHash(key)
            self.key = hash
        }
        
        if key.count < variant.blockSize() {
            self.key = CSZeroPadding().add(to: key, blockSize: variant.blockSize())
        }
    }
    
    public func authenticate(_ bytes: Array<UInt8>) throws -> Array<UInt8> {
        var opad = Array<UInt8>(repeating: 0x5c, count: variant.blockSize())
        for idx in self.key.indices {
            opad[idx] = self.key[idx] ^ opad[idx]
        }
        var ipad = Array<UInt8>(repeating: 0x36, count: variant.blockSize())
        for idx in self.key.indices {
            ipad[idx] = self.key[idx] ^ ipad[idx]
        }
        
        let ipadAndMessageHash = self.variant.calculateHash(ipad + bytes)
        let result = self.variant.calculateHash(opad + ipadAndMessageHash)
        
        // return Array(result[0..<10]) // 80 bits
        return result
    }
}

struct CSZeroPadding {
    init() {}
    
    func add(to bytes: Array<UInt8>, blockSize: Int) -> Array<UInt8> {
        let paddingCount = blockSize - (bytes.count % blockSize)
        if paddingCount > 0 {
            return bytes + Array<UInt8>(repeating: 0, count: paddingCount)
        }
        return bytes
    }
    
    func remove(from bytes: Array<UInt8>, blockSize _: Int?) -> Array<UInt8> {
        for (idx, value) in bytes.reversed().enumerated() {
            if value != 0 {
                return Array(bytes[0..<bytes.count - idx])
            }
        }
        return bytes
    }
}

struct PKCS7Padding {
    enum Error: Swift.Error {
        case invalidPaddingValue
    }
    
    init() {}
    
    func add(to bytes: Array<UInt8>, blockSize: Int) -> Array<UInt8> {
        let padding = UInt8(blockSize - (bytes.count % blockSize))
        var withPadding = bytes
        if padding == 0 {
            // If the original data is a multiple of N bytes, then an extra block of bytes with value N is added.
            withPadding += Array<UInt8>(repeating: UInt8(blockSize), count: Int(blockSize))
        } else {
            // The value of each added byte is the number of bytes that are added
            withPadding += Array<UInt8>(repeating: padding, count: Int(padding))
        }
        return withPadding
    }
    
    func remove(from bytes: Array<UInt8>, blockSize _: Int?) -> Array<UInt8> {
        guard !bytes.isEmpty, let lastByte = bytes.last else {
            return bytes
        }
        
        assert(!bytes.isEmpty, "Need bytes to remove padding")
        
        let padding = Int(lastByte) // last byte
        let finalLength = bytes.count - padding
        
        if finalLength < 0 {
            return bytes
        }
        
        if padding >= 1 {
            return Array(bytes[0..<finalLength])
        }
        return bytes
    }
}

enum CSPKCS5 {
    typealias Padding = PKCS7Padding
}

extension CSPKCS5 {
    struct PBKDF2 {
        public enum Error: Swift.Error {
            case invalidInput
            case derivedKeyTooLong
        }
        
        private let salt: Array<UInt8> // S
        fileprivate let iterations: Int // c
        private let numBlocks: Int // l
        private let dkLen: Int
        fileprivate let prf: CSHMAC
        
        public init(password: Array<UInt8>, salt: Array<UInt8>, iterations: Int = 2048 /* c */, keyLength: Int? = nil /* dkLen */, variant: CSHMAC.Variant = .sha512) throws {
            precondition(iterations > 0)
            
            let prf = CSHMAC(key: password, variant: variant)
            
            guard iterations > 0 && !salt.isEmpty else {
                throw Error.invalidInput
            }
            
            self.dkLen = keyLength ?? variant.digestLength
            let keyLengthFinal = Double(dkLen)
            let hLen = Double(prf.variant.digestLength)
            if keyLengthFinal > (pow(2, 32) - 1) * hLen {
                throw Error.derivedKeyTooLong
            }
            
            self.salt = salt
            self.iterations = iterations
            self.prf = prf
            
            self.numBlocks = Int(ceil(Double(keyLengthFinal) / hLen)) // l = ceil(keyLength / hLen)
        }
        
        public func calculate() throws -> Array<UInt8> {
            var ret = Array<UInt8>()
            ret.reserveCapacity(self.numBlocks * self.prf.variant.digestLength)
            for i in 1...self.numBlocks {
                // for each block T_i = U_1 ^ U_2 ^ ... ^ U_iter
                if let value = try calculateBlock(self.salt, blockNum: i) {
                    ret.append(contentsOf: value)
                }
            }
            return Array(ret.prefix(self.dkLen))
        }
    }
}

extension CSPKCS5.PBKDF2 {
    func ARR(_ i: Int) -> Array<UInt8> {
        var inti = Array<UInt8>(repeating: 0, count: 4)
        inti[0] = UInt8((i >> 24) & 0xff)
        inti[1] = UInt8((i >> 16) & 0xff)
        inti[2] = UInt8((i >> 8) & 0xff)
        inti[3] = UInt8(i & 0xff)
        return inti
    }
    
    func calculateBlock(_ salt: Array<UInt8>, blockNum: Int) throws -> Array<UInt8>? {
        guard let u1 = try? prf.authenticate(salt + ARR(blockNum)) else { // blockNum.bytes() is slower
            return nil
        }
        
        var u = u1
        var ret = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = try prf.authenticate(u)
                for x in 0..<ret.count {
                    ret[x] = ret[x] ^ u[x]
                }
            }
        }
        return ret
    }
}
