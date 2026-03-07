// OpalBase+PublicKey.swift

import Foundation

extension OpalBase {
    public struct PublicKey {
        let compressedData: Data
        
        public init(privateKey: OpalBase.PrivateKey) throws {
            self.compressedData = try Secp256k1Model.Operation.derivePublicKey(
                fromPrivateKey32: privateKey.rawData,
                format: .compressed
            )
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
        return ripemd160
    }
}

extension _OpalBase.PublicKey: Sendable {}
extension _OpalBase.PublicKey: Hashable {}
extension _OpalBase.PublicKey: Equatable {}
