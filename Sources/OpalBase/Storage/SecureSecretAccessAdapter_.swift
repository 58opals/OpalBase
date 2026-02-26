// SecureSecretAccessPort_.swift

import Foundation

public protocol SecureSecretAccessAdapter: Sendable {
    func saveMnemonic(_ mnemonic: StorageActor.MnemonicModel,
                      fallbackToPlaintext: Bool) async throws -> StorageActor.SecurityModel.ProtectionMode
    func loadMnemonicState() async throws -> (mnemonic: StorageActor.MnemonicModel, protectionMode: StorageActor.SecurityModel.ProtectionMode)?
}
