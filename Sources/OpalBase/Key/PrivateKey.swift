import Foundation
import BigInt

struct PrivateKey {
    let rawData: Data
    
    private let minimumValue = BigUInt(1)
    private let maximumValue = BigUInt(words: [0xbfd25e8cd0364140, 0xbaaedce6af48a03b, 0xfffffffffffffffe, 0xffffffffffffffff]) // 115792089237316195423570985008687907852837564279074904382605163141518161494336
    
    init() throws {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        var bigUIntValue: BigUInt
        
        repeat {
            let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard result == errSecSuccess else { throw Error.randomBytesGenerationFailed }
            
            bigUIntValue = BigUInt(Data(randomBytes))
        } while bigUIntValue >= maximumValue || bigUIntValue <= minimumValue
        
        self.rawData = Data(randomBytes)
    }
    
    init(data: Data) throws {
        let bigUIntValue = BigUInt(data)
        guard bigUIntValue <= maximumValue || bigUIntValue >= minimumValue else { throw Error.outOfBounds }
        self.rawData = data
    }
}

extension PrivateKey: Equatable {
    static func ==(lhs: PrivateKey, rhs: PrivateKey) -> Bool {
        return lhs.rawData == rhs.rawData
    }
}
