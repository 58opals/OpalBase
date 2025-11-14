// PrivateKey.swift

import Foundation
import BigInt

public struct PrivateKey {
    let rawData: Data
    
    private let minimumValue = BigUInt(1)
    private let maximumValue = BigUInt(words: [0xbfd25e8cd0364140, 0xbaaedce6af48a03b, 0xfffffffffffffffe, 0xffffffffffffffff]) // 115792089237316195423570985008687907852837564279074904382605163141518161494336
    
    public init() throws {
        var randomBytes: [UInt8] = .init()
        var bigUIntValue = BigUInt.zero
        
        repeat {
            do {
                randomBytes = try SecureRandom.makeBytes(count: 32)
            } catch {
                throw Error.randomBytesGenerationFailed
            }
            
            bigUIntValue = BigUInt(Data(randomBytes))
        } while bigUIntValue >= maximumValue || bigUIntValue <= minimumValue
        
        self.rawData = Data(randomBytes)
    }
    
    public init(data: Data) throws {
        let bigUIntValue = BigUInt(data)
        guard bigUIntValue >= minimumValue && bigUIntValue <= maximumValue else { throw Error.outOfBounds }
        self.rawData = data
    }
}

extension PrivateKey: Hashable {}
extension PrivateKey: Sendable {}
extension PrivateKey: Equatable {}

extension PrivateKey {
    enum Error: Swift.Error {
        case randomBytesGenerationFailed
        case outOfBounds
        case cannotDecodeWIF
        
        case invalidFormat
        case invalidLength
        case invalidVersion
        case invalidChecksum
        case invalidKeyPrefix
        case invalidStringKey
        case invalidDerivedKey
    }
}
