// LegacyStoredMnemonicPersistenceState.swift

@testable import OpalBase

actor LegacyStoredMnemonicPersistenceState {
    private var states: [
        String: (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )
    ] = [:]

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        generation: String,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    ) -> OpalBase.Storage.Security.ProtectionMode {
        states[generation] = (mnemonic, protectionMode)
        return protectionMode
    }

    func loadMnemonicState(
        generation: String
    ) -> (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )? {
        states[generation]
    }

    func deleteMnemonic(generation: String) {
        states[generation] = nil
    }
}
