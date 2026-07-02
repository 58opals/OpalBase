// OpalBase+Storage+Security+SecureEnclave.swift

import Foundation
import Security

extension _OpalBase.Storage.Security {
    public static func makeSecureEnclaveBacked(
        configuration: SecureEnclaveConfiguration = .init()
    ) throws -> Self {
        let applicationTag = Data(configuration.applicationTag.utf8)
        guard !applicationTag.isEmpty else {
            throw SecureEnclaveAdapter.makeSecurityError(
                status: errSecParam,
                message: "Secure Enclave application tag must not be empty."
            )
        }
        try SecureEnclaveAdapter.prepare(applicationTag: applicationTag)

        return .init(
            encrypt: { plaintext in
                try SecureEnclaveAdapter.encrypt(plaintext, applicationTag: applicationTag)
            },
            decrypt: { ciphertext in
                try SecureEnclaveAdapter.decrypt(ciphertext, applicationTag: applicationTag)
            },
            checkSecureEnclaveErrorRecoverability: { error in
                SecureEnclaveAdapter.isRecoverable(error)
            },
            protectedMaterialReset: {
                try SecureEnclaveAdapter.deleteKey(applicationTag: applicationTag)
            }
        )
    }
}
