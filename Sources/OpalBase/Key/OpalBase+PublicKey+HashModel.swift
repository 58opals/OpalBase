// OpalBase+PublicKey+HashModel.swift

import Foundation

extension _OpalBase.PublicKey {
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

extension _OpalBase.PublicKey.HashModel: Sendable {}
extension _OpalBase.PublicKey.HashModel: Hashable {}
extension _OpalBase.PublicKey.HashModel: Equatable {}
