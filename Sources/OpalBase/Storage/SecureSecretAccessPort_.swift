// SecureSecretAccessPort_.swift

import Foundation

public protocol SecureSecretAccessPort: Sendable {
    func saveMnemonic(_ mnemonic: Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> Storage.Security.ProtectionMode
    func loadMnemonicState() async throws -> (mnemonic: Storage.Mnemonic, protectionMode: Storage.Security.ProtectionMode)?
}
