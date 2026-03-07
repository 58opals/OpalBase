// OpalBase.PublicKey+HashModel.swift

import Foundation

extension OpalBase {
    public struct PublicKey {
    let compressedData: Data
    
    public init(privateKey: OpalBase.PrivateKey) throws {
        self.compressedData = try Secp256k1Model.OperationModel.derivePublicKey(fromPrivateKey32: privateKey.rawData, format: .compressed)
    }
    
    public init(compressedData: Data) throws {
        guard compressedData.count == 33 else { throw Error.invalidLength }
        self.compressedData = compressedData
    }
    }
}

extension _OpalBase.PublicKey {
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
        
        init(publicKey: OpalBase.PublicKey) {
            self.data = publicKey.hash
        }
    }
}

extension _OpalBase.PublicKey: Sendable {}
extension _OpalBase.PublicKey: Hashable {}
extension _OpalBase.PublicKey: Equatable {}
extension _OpalBase.PublicKey.HashModel: Sendable {}
extension _OpalBase.PublicKey.HashModel: Hashable {}
extension _OpalBase.PublicKey.HashModel: Equatable {}

extension _OpalBase.PublicKey {
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

