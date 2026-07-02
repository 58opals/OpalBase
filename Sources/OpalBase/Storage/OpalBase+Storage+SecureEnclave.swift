// OpalBase+Storage+SecureEnclave.swift

extension _OpalBase.Storage {
    public static func makeSecureEnclaveBacked(
        valueClient: ValueClient,
        configuration: Security.SecureEnclaveConfiguration = .init()
    ) throws -> Self {
        let security = try Security.makeSecureEnclaveBacked(configuration: configuration)
        return try Self(valueClient: valueClient, security: security)
    }
}
