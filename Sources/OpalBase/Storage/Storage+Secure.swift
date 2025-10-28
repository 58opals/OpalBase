// Storage+Secure.swift

import Foundation
import Security

extension Storage {
    public struct SecureStore: Sendable {
        public struct Options: Sendable {
            public var accessGroup: String?
            public var shouldUseSecureEnclave: Bool
            
            public init(accessGroup: String? = nil, shouldUseSecureEnclave: Bool = false) {
                self.accessGroup = accessGroup
                self.shouldUseSecureEnclave = shouldUseSecureEnclave
            }
        }
        public enum Error: Swift.Error {
            case keychainFailure(OSStatus)
            case secureEnclaveFailure
        }
        
        private let options: Options
        private let serviceName = "com.58opals.opal.storage.secure"
        private let secureEnclaveKeyIdentifier = "secure-enclave-key.v1"
        
        public init(options: Options = .init()) {
            self.options = options
        }
        
        public func saveValue(_ value: Data, forAccount account: String) throws {
            let preparedData = try prepareDataForStorage(value)
            var addAttributes = makeKeychainAttributes(forAccount: account)
            addAttributes[kSecValueData as String] = preparedData
            addAttributes[kSecAttrAccessible as String] = keychainAccessibilityAttribute
            
            let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                let updateQuery = makeKeychainAttributes(forAccount: account)
                let updateAttributes: [String: Any] = [
                    kSecValueData as String: preparedData,
                    kSecAttrAccessible as String: keychainAccessibilityAttribute
                ]
                let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
                guard updateStatus == errSecSuccess else { throw Error.keychainFailure(updateStatus) }
            } else if addStatus != errSecSuccess {
                throw Error.keychainFailure(addStatus)
            }
        }
        
        public func loadValue(forAccount account: String) throws -> Data? {
            var query = makeKeychainAttributes(forAccount: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            
            var output: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &output)
            if status == errSecItemNotFound {
                return nil
            }
            guard status == errSecSuccess else { throw Error.keychainFailure(status) }
            guard let storedData = output as? Data else { return nil }
            return try recoverStoredData(storedData)
        }
        
        public func removeValue(forAccount account: String) throws {
            let query = makeKeychainAttributes(forAccount: account)
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.keychainFailure(status) }
        }
        public func hasValue(forAccount account: String) throws -> Bool {
            return try loadValue(forAccount: account) != nil
        }
    }
}

extension Storage.SecureStore {
    var keychainAccessibilityAttribute: CFString {
        options.shouldUseSecureEnclave ? kSecAttrAccessibleWhenUnlockedThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
    }
    
    func makeKeychainAttributes(forAccount account: String) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        if let accessGroup = options.accessGroup {
            attributes[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return attributes
    }
    
    func prepareDataForStorage(_ value: Data) throws -> Data {
        guard options.shouldUseSecureEnclave else { return value }
        let privateKey = try loadOrCreateSecureEnclavePrivateKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw Error.secureEnclaveFailure }
        let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else { throw Error.secureEnclaveFailure }
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, value as CFData, nil) as Data? else {
            throw Error.secureEnclaveFailure
        }
        return encryptedData
    }
    
    func recoverStoredData(_ data: Data) throws -> Data {
        guard options.shouldUseSecureEnclave else { return data }
        let privateKey = try loadOrCreateSecureEnclavePrivateKey()
        let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else { throw Error.secureEnclaveFailure }
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, algorithm, data as CFData, nil) as Data? else {
            throw Error.secureEnclaveFailure
        }
        return decryptedData
    }
    
    func loadOrCreateSecureEnclavePrivateKey() throws -> SecKey {
        if let existingKey = copySecureEnclavePrivateKey() {
            return existingKey
        }
        
        guard let accessControl = SecAccessControlCreateWithFlags(nil,
                                                                  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                                  [.privateKeyUsage],
                                                                  nil) else { throw Error.secureEnclaveFailure }
        
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
    
    func copySecureEnclavePrivateKey() -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: secureEnclaveApplicationTag(),
            kSecReturnRef as String: true
        ]
        if let accessGroup = options.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var output: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &output)
        guard status == errSecSuccess else { return nil }
        return (output as! SecKey)
    }
    
    func secureEnclaveApplicationTag() -> Data {
        Data(secureEnclaveKeyIdentifier.utf8)
    }
}
