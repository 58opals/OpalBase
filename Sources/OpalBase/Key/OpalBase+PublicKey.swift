// OpalBase+PublicKey.swift

import Foundation

extension OpalBase {
    public struct PublicKey {
        let compressedData: Data
        
        public init(compressedData: Data) throws {
            guard compressedData.count == 33 else { throw Error.invalidLength }
            self.compressedData = compressedData
        }

        init(privateKeyData: Data) throws {
            self.compressedData = try OpalCryptoAdapter.deriveCompressedPublicKey(from: privateKeyData)
        }
    }
}

extension _OpalBase.PublicKey {
    public var hash: Data {
        OpalCryptoAdapter.hash160(compressedData)
    }
}

extension _OpalBase.PublicKey: Sendable {}
extension _OpalBase.PublicKey: Hashable {}
extension _OpalBase.PublicKey: Equatable {}
