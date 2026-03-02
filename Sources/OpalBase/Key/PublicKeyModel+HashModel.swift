// PublicKeyModel.swift

import Foundation
import OpalCrypto

public struct PublicKeyModel {
    let compressedData: Data
    
    public init(privateKey: PrivateKeyModel) throws {
        self.compressedData = try StandardsForEfficientCryptography256k1CurveModel.OperationModel.derivePublicKey(fromPrivateKeyData32Bytes: privateKey.rawData, format: .compressed)
    }
    
    public init(compressedData: Data) throws {
        guard compressedData.count == 33 else { throw Error.invalidLength }
        self.compressedData = compressedData
    }
}

extension PublicKeyModel {
    public var hash: Data {
        SecureHash160Model.hash(compressedData)
    }
    
    public struct HashModel {
        let data: Data
        
        init(_ data: Data) {
            self.data = data
        }
        
        init(publicKey: PublicKeyModel) {
            self.data = publicKey.hash
        }
    }
}

extension PublicKeyModel: Sendable {}
extension PublicKeyModel: Hashable {}
extension PublicKeyModel: Equatable {}
extension PublicKeyModel.HashModel: Sendable {}
extension PublicKeyModel.HashModel: Hashable {}
extension PublicKeyModel.HashModel: Equatable {}

extension PublicKeyModel {
    enum Error: Swift.Error {
        case invalidFormat
        case invalidLength
        case invalidVersion
        case invalidChecksum
        case hardenedDerivation
        case publicKeyDerivationFailed
        case derivationPathTooShort
    }
}
