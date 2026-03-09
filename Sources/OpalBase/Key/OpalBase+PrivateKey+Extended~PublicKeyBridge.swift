// OpalBase+PrivateKey+Extended~PublicKeyBridge.swift

import Foundation

extension _OpalBase.PrivateKey.Extended {
    func deriveExtendedPublicKey() throws -> OpalBase.PublicKey.Extended { try .init(extendedPrivateKey: self) }

    func deriveChildPublicKey(at path: OpalBase.DerivationPath) throws -> OpalBase.PublicKey.Extended {
        let child = try deriveChild(at: path)
        return try .init(extendedPrivateKey: child)
    }
}
