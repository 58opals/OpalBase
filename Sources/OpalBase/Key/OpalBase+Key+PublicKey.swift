// OpalBase+Key+PublicKey.swift

import Foundation

extension _OpalBase.Key {
    public struct PublicKey {
        public let compressedData: Data
        
        public init(compressedData: Data) throws {
            guard compressedData.count == 33 else { throw Error.invalidLength }
            do {
                self.compressedData = try OpalCryptoAdapter.validateCompressedPublicKey(
                    Data(compressedData)
                )
            } catch {
                throw Error.invalidFormat
            }
        }

        init(privateKeyData: Data) throws {
            self.compressedData = try OpalCryptoAdapter.deriveCompressedPublicKey(from: privateKeyData)
        }
    }
}

extension _OpalBase.Key.PublicKey {
    public var hash: Data {
        OpalCryptoAdapter.hash160(compressedData)
    }
}

extension _OpalBase.Key.PublicKey: Sendable {}
extension _OpalBase.Key.PublicKey: Hashable {}
extension _OpalBase.Key.PublicKey: Equatable {}
