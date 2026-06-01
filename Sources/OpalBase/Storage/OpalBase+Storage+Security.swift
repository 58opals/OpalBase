// OpalBase+Storage+Security.swift

import Foundation

extension _OpalBase.Storage {
    public struct Security: Sendable {
        public enum Error: Swift.Error {
            case protectionUnavailable
            case insufficientProtection(required: ProtectionMode, actual: ProtectionMode)
            case encryptionFailure(Swift.Error)
            case decryptionFailure(Swift.Error)
        }
        
        public enum ProtectionMode: String, Codable, Sendable {
            case secureEnclave
            case software
            case plaintext
        }

        public enum PersistencePolicy: Sendable, Equatable {
            case acceptProviderOutput
            case legacyFallbackToPlaintext
            case requireSecureEnclave
        }

        public struct SecureEnclaveConfiguration: Sendable {
            public let applicationTag: String

            public init(applicationTag: String = "OpalBase.Storage.Security.SecureEnclave") {
                self.applicationTag = applicationTag
            }
        }
        
        public struct Ciphertext: Codable, Sendable {
            public let mode: ProtectionMode
            public let payload: Data
            
            public init(mode: ProtectionMode, payload: Data) {
                self.mode = mode
                self.payload = Data(payload)
            }
        }
        
        public typealias Encrypt = @Sendable (Data) throws -> Ciphertext
        public typealias Decrypt = @Sendable (Ciphertext) throws -> Data
        public typealias RecoverableSecureFailure = @Sendable (Swift.Error) -> Bool
        typealias ProtectedMaterialReset = @Sendable () throws -> Void
        
        private let encryptor: Encrypt?
        private let decryptor: Decrypt?
        private let isSecureFailureRecoverable: RecoverableSecureFailure
        private let protectedMaterialReset: ProtectedMaterialReset?
        
        public init(encrypt: Encrypt? = nil,
                    decrypt: Decrypt? = nil,
                    checkSecureEnclaveErrorRecoverability: @escaping RecoverableSecureFailure = { _ in false }) {
            self.init(
                encrypt: encrypt,
                decrypt: decrypt,
                checkSecureEnclaveErrorRecoverability: checkSecureEnclaveErrorRecoverability,
                protectedMaterialReset: nil
            )
        }

        init(encrypt: Encrypt? = nil,
             decrypt: Decrypt? = nil,
             checkSecureEnclaveErrorRecoverability: @escaping RecoverableSecureFailure = { _ in false },
            protectedMaterialReset: ProtectedMaterialReset? = nil) {
            if let encrypt {
                self.encryptor = { value in
                    try encrypt(Data(value))
                }
            } else {
                self.encryptor = nil
            }
            if let decrypt {
                self.decryptor = { ciphertext in
                    try Data(decrypt(ciphertext))
                }
            } else {
                self.decryptor = nil
            }
            self.isSecureFailureRecoverable = checkSecureEnclaveErrorRecoverability
            self.protectedMaterialReset = protectedMaterialReset
        }
        
        public static func makePlaintextOnly() -> Self {
            .init(encrypt: { value in
                Ciphertext(mode: .plaintext, payload: value)
            }, decrypt: { ciphertext in
                ciphertext.payload
            }, checkSecureEnclaveErrorRecoverability: { error in
                guard case Error.protectionUnavailable = error else { return false }
                return true
            })
        }
        
        public func encrypt(_ value: Data) throws -> Ciphertext {
            guard let encryptor else { throw Error.protectionUnavailable }
            do {
                return try encryptor(value)
            } catch {
                throw Error.encryptionFailure(error)
            }
        }
        
        public func decrypt(_ ciphertext: Ciphertext) throws -> Data {
            guard let decryptor else { throw Error.protectionUnavailable }
            do {
                return try decryptor(ciphertext)
            } catch {
                throw Error.decryptionFailure(error)
            }
        }
        
        public func checkSecureEnclaveErrorRecoverability(_ error: Swift.Error) -> Bool {
            isSecureFailureRecoverable(error)
        }

        func resetProtectedMaterial() throws {
            try protectedMaterialReset?()
        }
    }
}
