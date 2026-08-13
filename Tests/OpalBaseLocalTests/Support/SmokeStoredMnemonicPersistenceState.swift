// SmokeStoredMnemonicPersistenceState.swift

@testable import OpalBase

actor SmokeStoredMnemonicPersistenceState {
    private var state: (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )?

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        policy: OpalBase.Storage.Security.PersistencePolicy
    ) -> OpalBase.Storage.Security.ProtectionMode {
        let mode: OpalBase.Storage.Security.ProtectionMode =
            policy == .legacyFallbackToPlaintext ? .plaintext : .software
        state = (mnemonic, mode)
        return mode
    }

    func loadMnemonicState() -> (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )? {
        state
    }

    func deleteMnemonic(generation _: String) {
        state = nil
    }
}
