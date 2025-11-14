// Storage+Security.swift

import Foundation
import Security

extension Storage {
    public struct Security: Sendable {
        public struct Options: Sendable {
            public var accessGroup: String?
            
            public init(accessGroup: String? = nil) {
                self.accessGroup = accessGroup
            }
        }
        public enum Error: Swift.Error {
            case keychainFailure(OSStatus)
            case secureEnclaveFailure
            case softwareCryptoFailure(Swift.Error)
            case randomGenerationFailure(Int32)
            case missingCombinedCiphertext
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
        
        let options: Options
        let secureEnclaveKeyIdentifier = "secure-enclave-key.v1"
        let softwareKeyIdentifier = "software-symmetric-key.v1"
        
        public init(options: Options = .init()) {
            self.options = options
        }
        
        public func encrypt(_ value: Data) throws -> Ciphertext {
            do {
                let ciphertext = try encryptWithSecureEnclave(value)
                return Ciphertext(mode: .secureEnclave, payload: ciphertext)
            } catch {
                guard isRecoverableSecureEnclaveError(error) else { throw error }
                let fallbackCiphertext = try encryptWithSoftwareCrypto(value)
                return Ciphertext(mode: .software, payload: fallbackCiphertext)
            }
        }
        
        public func decrypt(_ ciphertext: Ciphertext) throws -> Data {
            switch ciphertext.mode {
            case .secureEnclave:
                return try decryptWithSecureEnclave(ciphertext.payload)
            case .software:
                return try decryptWithSoftwareCrypto(ciphertext.payload)
            case .plaintext:
                return ciphertext.payload
            }
        }
        
        public func isRecoverableSecureEnclaveError(_ error: Swift.Error) -> Bool {
            guard let securityError = error as? Error else { return false }
            switch securityError {
            case .secureEnclaveFailure:
                return true
            case .keychainFailure(let status):
                return isSecureEnclaveRelated(status: status)
            case .softwareCryptoFailure,
                    .randomGenerationFailure,
                    .missingCombinedCiphertext:
                return false
            }
        }
    }
}

extension Storage.Security {
    var keychainAccessibilityAttribute: CFString {
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    
    func loadOrCreateSecureEnclavePrivateKey() throws -> SecKey {
        if let existingKey = try copySecureEnclavePrivateKey() {
            return existingKey
        }
        
        let accessControl = try makeSecureEnclaveAccessControl()
        var privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: secureEnclaveApplicationTag(),
            kSecAttrAccessControl as String: accessControl
        ]
        if let accessGroup = options.accessGroup {
            privateKeyAttributes[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateKeyAttributes
        ]
        
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw Error.secureEnclaveFailure
        }
        return privateKey
    }
    
    func copySecureEnclavePrivateKey() throws -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: secureEnclaveApplicationTag(),
            kSecReturnRef as String: true,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrAccessible as String: keychainAccessibilityAttribute,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave
        ]
        if let accessGroup = options.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var output: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &output)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else { throw Error.keychainFailure(status) }
        guard let anyRef = output else { throw Error.secureEnclaveFailure }
        guard CFGetTypeID(anyRef) == SecKeyGetTypeID() else { throw Error.secureEnclaveFailure }
        return unsafeDowncast(anyRef, to: SecKey.self)
    }
    
    func makeSecureEnclaveAccessControl() throws -> SecAccessControl {
        guard let accessControl = SecAccessControlCreateWithFlags(nil,
                                                                  keychainAccessibilityAttribute,
                                                                  [.privateKeyUsage],
                                                                  nil) else { throw Error.secureEnclaveFailure }
        return accessControl
    }
    
    func secureEnclaveApplicationTag() -> Data {
        Data(secureEnclaveKeyIdentifier.utf8)
    }
    
    func encryptWithSecureEnclave(_ value: Data) throws -> Data {
        let privateKey = try loadOrCreateSecureEnclavePrivateKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw Error.secureEnclaveFailure }
        let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else { throw Error.secureEnclaveFailure }
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, value as CFData, nil) as Data? else {
            throw Error.secureEnclaveFailure
        }
        return encryptedData
    }
    
    func decryptWithSecureEnclave(_ value: Data) throws -> Data {
        let privateKey = try loadOrCreateSecureEnclavePrivateKey()
        let algorithm = SecKeyAlgorithm.eciesEncryptionStandardX963SHA256AESGCM
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else { throw Error.secureEnclaveFailure }
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, algorithm, value as CFData, nil) as Data? else {
            throw Error.secureEnclaveFailure
        }
        return decryptedData
    }
    
    func isSecureEnclaveRelated(status: OSStatus) -> Bool {
        switch status {
        case errSecInteractionNotAllowed,
            errSecDecode,
            errSecAuthFailed,
            errSecNotAvailable,
            errSecMissingEntitlement,
            errSecParam,
        errSecUnimplemented:
            return true
        default:
            return false
        }
    }
}
