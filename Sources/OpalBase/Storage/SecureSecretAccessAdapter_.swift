// SecureSecretAccessAdapter_.swift

import Foundation

public protocol SecureSecretAccessAdapter: Sendable {
    func saveMnemonic(_ mnemonic: OpalBase.Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> OpalBase.Storage.SecurityModel.ProtectionMode
    func loadMnemonicState() async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: OpalBase.Storage.SecurityModel.ProtectionMode)?
}
