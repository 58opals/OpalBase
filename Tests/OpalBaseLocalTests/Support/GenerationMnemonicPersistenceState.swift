// GenerationMnemonicPersistenceState.swift

@testable import OpalBase

actor GenerationMnemonicPersistenceState {
    private var mnemonicStates: [String: (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )] = .init()
    private var shouldFailNextSave = false
    private var shouldFailNextDelete = false

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        generation: String,
        fallbackToPlaintext: Bool
    ) throws -> OpalBase.Storage.Security.ProtectionMode {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw GenerationPersistenceError.simulatedFailure
        }

        let mode: OpalBase.Storage.Security.ProtectionMode = fallbackToPlaintext ? .plaintext : .software
        mnemonicStates[generation] = (mnemonic, mode)
        return mode
    }

    func loadMnemonicState(generation: String) -> (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )? {
        mnemonicStates[generation]
    }

    func deleteMnemonic(generation: String) throws {
        if shouldFailNextDelete {
            shouldFailNextDelete = false
            throw GenerationPersistenceError.simulatedFailure
        }

        mnemonicStates.removeValue(forKey: generation)
    }

    func failNextSave() {
        shouldFailNextSave = true
    }

    func failNextDelete() {
        shouldFailNextDelete = true
    }
}
