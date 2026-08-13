// OpalBase+Storage+SecureEnclave.swift

extension _OpalBase.Storage {
    /// Creates Secure Enclave-backed storage that requires Secure Enclave protection for every mnemonic write.
    public static func makeSecureEnclaveBacked(
        valueClient: ValueClient,
        configuration: Security.SecureEnclaveConfiguration = .init()
    ) throws -> Self {
        let security = try Security.makeSecureEnclaveBacked(configuration: configuration)
        return try Self(
            valueClient: valueClient,
            security: security,
            secretPersistencePolicy: .requireSecureEnclave
        )
    }
}
