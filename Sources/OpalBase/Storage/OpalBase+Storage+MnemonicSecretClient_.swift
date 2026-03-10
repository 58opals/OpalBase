// OpalBase+Storage+MnemonicSecretClient_.swift

import Foundation

extension _OpalBase.Storage {
    public protocol MnemonicSecretClient: Sendable {
        func saveMnemonic(_ mnemonic: OpalBase.Storage.Mnemonic,
                          fallbackToPlaintext: Bool) async throws -> OpalBase.Storage.Security.ProtectionMode
        func loadMnemonicState() async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
    }
}
