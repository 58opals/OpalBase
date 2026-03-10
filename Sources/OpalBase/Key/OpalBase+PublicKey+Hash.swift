// OpalBase+PublicKey+Hash.swift

import Foundation

extension _OpalBase.PublicKey {
    public struct Hash {
        let data: Data
        
        init(_ data: Data) {
            self.data = data
        }
        
        init(publicKey: OpalBase.PublicKey) {
            self.data = publicKey.hash
        }
    }
}

extension _OpalBase.PublicKey.Hash: Sendable {}
extension _OpalBase.PublicKey.Hash: Hashable {}
extension _OpalBase.PublicKey.Hash: Equatable {}
