// RegistryClientErrorCaptureFailure.swift

enum RegistryClientErrorCaptureFailure: Swift.Error {
    case didNotThrow
    case unexpectedClientError(String)
    case unexpectedError(String)
}
