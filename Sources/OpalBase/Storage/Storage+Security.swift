// Storage+Security.swift

import Foundation

extension Storage {
    public struct Security: Sendable {
        public enum Error: Swift.Error {
            case protectionUnavailable
            case encryptionFailure(Swift.Error)
            case decryptionFailure(Swift.Error)
        }
        
        public enum ProtectionMode: String, Codable, Sendable {
            case secureEnclave
            case software
            case plaintext
        }
        
        public struct Ciphertext: Codable, Sendable {
            public let mode: ProtectionMode
            public let payload: Data
            
            public init(mode: ProtectionMode, payload: Data) {
                self.mode = mode
                self.payload = payload
            }
        }
        
        public typealias Encrypt = @Sendable (Data) throws -> Ciphertext
        public typealias Decrypt = @Sendable (Ciphertext) throws -> Data
        public typealias RecoverableSecureFailure = @Sendable (Swift.Error) -> Bool
        
        private let encryptValue: Encrypt?
        private let decryptValue: Decrypt?
        private let recoverableSecureFailure: RecoverableSecureFailure
        
        public init(encrypt: Encrypt? = nil,
                    decrypt: Decrypt? = nil,
                    isRecoverableSecureEnclaveError: @escaping RecoverableSecureFailure = { _ in false }) {
            self.encryptValue = encrypt
            self.decryptValue = decrypt
            self.recoverableSecureFailure = isRecoverableSecureEnclaveError
        }
        
        public static func makePlaintextOnly() -> Self {
            .init(encrypt: { value in
                Ciphertext(mode: .plaintext, payload: value)
            }, decrypt: { ciphertext in
                ciphertext.payload
            }, isRecoverableSecureEnclaveError: { error in
                guard case Error.protectionUnavailable = error else { return false }
                return true
            })
        }
        
        public func encrypt(_ value: Data) throws -> Ciphertext {
            guard let encryptValue else { throw Error.protectionUnavailable }
            do {
                return try encryptValue(value)
            } catch {
                throw Error.encryptionFailure(error)
            }
        }
        
        public func decrypt(_ ciphertext: Ciphertext) throws -> Data {
            guard let decryptValue else { throw Error.protectionUnavailable }
            do {
                return try decryptValue(ciphertext)
            } catch {
                throw Error.decryptionFailure(error)
            }
        }
        
        public func isRecoverableSecureEnclaveError(_ error: Swift.Error) -> Bool {
            recoverableSecureFailure(error)
        }
    }
}
