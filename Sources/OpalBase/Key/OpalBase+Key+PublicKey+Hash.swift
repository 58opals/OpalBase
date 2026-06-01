// OpalBase+Key+PublicKey+Hash.swift

import Foundation

extension _OpalBase.Key.PublicKey {
    public struct Hash {
        let data: Data
        
        init(_ data: Data) {
            self.data = Data(data)
        }
        
        init(publicKey: OpalBase.Key.PublicKey) {
            self.init(publicKey.hash)
        }
    }
}

extension _OpalBase.Key.PublicKey.Hash: Sendable {}
extension _OpalBase.Key.PublicKey.Hash: Hashable {}
extension _OpalBase.Key.PublicKey.Hash: Equatable {}
