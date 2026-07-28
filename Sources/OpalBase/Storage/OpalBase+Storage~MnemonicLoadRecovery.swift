// OpalBase+Storage~MnemonicLoadRecovery.swift

extension _OpalBase.Storage {
    static func isRecoverableMnemonicLoadFailure(
        _ error: Swift.Error,
        security: OpalBase.Storage.Security
    ) -> Bool {
        switch error {
        case OpalBase.Storage.Error.secureStoreFailure(let underlying),
            OpalBase.Storage.Security.Error.encryptionFailure(let underlying),
            OpalBase.Storage.Security.Error.decryptionFailure(let underlying):
            return isRecoverableMnemonicLoadFailure(underlying, security: security)
        case OpalBase.Storage.Security.Error.protectionUnavailable,
            OpalBase.Storage.Security.Error.insufficientProtection:
            return true
        default:
            return security.checkSecureEnclaveErrorRecoverability(error)
        }
    }
}
