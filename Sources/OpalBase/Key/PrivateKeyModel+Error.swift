// PrivateKeyModel+Error.swift

import Foundation

public struct PrivateKeyModel {
    let rawData: Data
    
    public init() throws {
        var randomBytes: [UInt8] = .init()
        var isValidPrivateKey = false
        
        repeat {
            do {
                randomBytes = try SecureRandomModel.makeBytes(count: 32)
            } catch {
                throw Error.randomBytesGenerationFailed
            }
            
            isValidPrivateKey = Secp256k1Model.OperationModel.validatePrivateKey32(Data(randomBytes))
        } while !isValidPrivateKey
        
        self.rawData = Data(randomBytes)
    }
    
    public init(data: Data) throws {
        guard Secp256k1Model.OperationModel.validatePrivateKey32(data) else { throw Error.outOfBounds }
        self.rawData = data
    }
}

extension PrivateKeyModel: Sendable {}
extension PrivateKeyModel: Hashable {}
extension PrivateKeyModel: Equatable {}

extension PrivateKeyModel {
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
        case derivationPathTooShort
    }
}

