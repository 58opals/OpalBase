// OpalBase.PrivateKey+ExtendedModel~PublicKeyBridge.swift

import Foundation

extension _OpalBase.PrivateKey.ExtendedModel {
    func deriveExtendedPublicKey() throws -> OpalBase.PublicKey.ExtendedModel { try .init(extendedPrivateKey: self) }

    func deriveChildPublicKey(at path: OpalBase.DerivationPath) throws -> OpalBase.PublicKey.ExtendedModel {
        let child = try deriveChild(at: path)
        return try .init(extendedPrivateKey: child)
    }
}
