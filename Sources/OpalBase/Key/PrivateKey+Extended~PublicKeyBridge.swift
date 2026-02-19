// PrivateKey+Extended~PublicKeyBridge.swift

import Foundation

extension PrivateKey.Extended {
    func deriveExtendedPublicKey() throws -> PublicKey.Extended { try .init(extendedPrivateKey: self) }

    func deriveChildPublicKey(at path: DerivationPath) throws -> PublicKey.Extended {
        let child = try deriveChild(at: path)
        return try .init(extendedPrivateKey: child)
    }
}
