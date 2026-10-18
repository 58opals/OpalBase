// OpalBase+Key+PublicKey+Hash.swift

import Foundation

extension _OpalBase.Key.PublicKey {
    public struct Hash {
        package let data: Data
        
        package init(_ data: Data) {
            self.data = Data(data)
        }
        
        package init(publicKey: OpalBase.Key.PublicKey) {
            self.init(publicKey.hash)
        }
    }
}

extension _OpalBase.Key.PublicKey.Hash: Sendable {}
extension _OpalBase.Key.PublicKey.Hash: Hashable {}
extension _OpalBase.Key.PublicKey.Hash: Equatable {}
