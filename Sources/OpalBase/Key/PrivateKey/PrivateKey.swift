// PrivateKey.swift

import Foundation
import SwiftSchnorr

public struct PrivateKey {
    let rawData: Data
    
    public init() throws {
        var randomBytes: [UInt8] = .init()
        var isValidPrivateKey = false
        
        repeat {
            do {
                randomBytes = try SecureRandom.makeBytes(count: 32)
            } catch {
                throw Error.randomBytesGenerationFailed
            }
            
            isValidPrivateKey = Secp256k1KeyOperations.isValidPrivateKey32(Data(randomBytes))
        } while !isValidPrivateKey
        
        self.rawData = Data(randomBytes)
    }
    
    public init(data: Data) throws {
        guard Secp256k1KeyOperations.isValidPrivateKey32(data) else { throw Error.outOfBounds }
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
