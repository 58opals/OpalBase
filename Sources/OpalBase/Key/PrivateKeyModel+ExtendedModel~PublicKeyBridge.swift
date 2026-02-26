// PrivateKeyModel+ExtendedModel~PublicKeyBridge.swift

import Foundation

extension PrivateKeyModel.ExtendedModel {
    func deriveExtendedPublicKey() throws -> PublicKeyModel.ExtendedModel { try .init(extendedPrivateKey: self) }

    func deriveChildPublicKey(at path: DerivationPathModel) throws -> PublicKeyModel.ExtendedModel {
        let child = try deriveChild(at: path)
        return try .init(extendedPrivateKey: child)
    }
}
