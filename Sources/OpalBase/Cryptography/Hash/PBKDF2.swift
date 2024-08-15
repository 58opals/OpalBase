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
    func intToByteArray(_ value: Int) -> Array<UInt8> {
        var byteArray = Array<UInt8>(repeating: 0, count: 4)
        byteArray[0] = UInt8((value >> 24) & 0xff)
        byteArray[1] = UInt8((value >> 16) & 0xff)
        byteArray[2] = UInt8((value >> 8) & 0xff)
        byteArray[3] = UInt8(value & 0xff)
        return byteArray
    }
    
    func computeBlock(_ saltBytes: Array<UInt8>, blockNum: Int) throws -> Array<UInt8>? {
        let u1 = HMAC<SHA512>.authenticationCode(for: saltBytes + intToByteArray(blockNum), using: symmetricKey)
        
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


/*
struct PBKDF2SHA512 {
    enum Error: Swift.Error {
        case invalidInput
        case derivedKeyTooLong
    }
    
    private let symmetricKey: SymmetricKey
    private let salt: Array<UInt8> // S
    private let iterations: Int // c
    private let numBlocks: Int // l
    private let dkLen: Int
    private let prf: HMAC<SHA512>
    
    private let sha512DigestLength = (512 / 8)
    
    public init(password: Array<UInt8>, salt: Array<UInt8>, iterations: Int = 4096 /* c */, keyLength: Int? = nil /* dkLen */) throws {
        precondition(iterations > 0)
        let symmetricKey = SymmetricKey(data: password)
        
        let prf = HMAC<SHA512>.init(key: symmetricKey)
        
        guard iterations > 0 && !salt.isEmpty else { throw Error.invalidInput }
        
        self.dkLen = keyLength ?? sha512DigestLength
        let keyLengthFinal = Double(dkLen)
        let hLen = Double(sha512DigestLength)
        if keyLengthFinal > (pow(2, 32) - 1) * hLen { throw Error.derivedKeyTooLong }
        
        self.symmetricKey = symmetricKey
        self.salt = salt
        self.iterations = iterations
        self.prf = prf
        
        self.numBlocks = Int(ceil(Double(keyLengthFinal) / hLen)) // l = ceil(keyLength / hLen)
    }
    
    public func calculate() throws -> Array<UInt8> {
        var ret = Array<UInt8>()
        ret.reserveCapacity(self.numBlocks * sha512DigestLength)
        for i in 1...self.numBlocks {
            if let value = try calculateBlock(self.salt, blockNum: i) {
                ret.append(contentsOf: value)
            }
        }
        return Array(ret.prefix(self.dkLen))
    }
    
    public func callAsFunction() throws -> Array<UInt8> {
        try calculate()
    }
}

private extension PBKDF2SHA512 {
    func ARR(_ i: Int) -> Array<UInt8> {
        var inti = Array<UInt8>(repeating: 0, count: 4)
        inti[0] = UInt8((i >> 24) & 0xff)
        inti[1] = UInt8((i >> 16) & 0xff)
        inti[2] = UInt8((i >> 8) & 0xff)
        inti[3] = UInt8(i & 0xff)
        return inti
    }
    
    func calculateBlock(_ salt: Array<UInt8>, blockNum: Int) throws -> Array<UInt8>? {
        let u1 = HMAC<SHA512>.authenticationCode(for: salt + ARR(blockNum), using: symmetricKey)
        
        var u = u1.bytes
        var ret = u.bytes
        if iterations > 1 {
            for _ in 2...iterations {
                u = HMAC<SHA512>.authenticationCode(for: u, using: symmetricKey).bytes
                for x in 0..<ret.count {
                    ret[x] = ret[x] ^ u[x]
                }
            }
        }
        return ret
    }
}
*/

/*
import Foundation
import CryptoSwift

struct PBKDF2 {
    static func hash(password: String, salt: String, iterations: Int = 2048, keyLength: Int = 64) throws -> Data {
        let password: Array<UInt8> = Data(password.utf8).bytes
        let salt: Array<UInt8> = Data(salt.utf8).bytes
        let pbkdf2 = try PKCS5.PBKDF2(password: password, salt: salt, iterations: iterations, keyLength: keyLength, variant: .sha2(.sha512)).calculate()
        
        return Data(pbkdf2)
    }
}
*/

