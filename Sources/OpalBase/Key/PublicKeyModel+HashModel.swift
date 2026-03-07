// PublicKeyModel+HashModel.swift

import Foundation

public struct PublicKeyModel {
    let compressedData: Data
    
    public init(privateKey: PrivateKeyModel) throws {
        self.compressedData = try Secp256k1Model.OperationModel.derivePublicKey(fromPrivateKey32: privateKey.rawData, format: .compressed)
    }
    
    public init(compressedData: Data) throws {
        guard compressedData.count == 33 else { throw Error.invalidLength }
        self.compressedData = compressedData
    }
}

extension PublicKeyModel {
    public var hash: Data {
        let sha256 = SHA256Model.hash(compressedData)
        let ripemd160 = RIPEMD160Model.hash(sha256)
        let hash = ripemd160
        return hash
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

