// Storage+Security~Software.swift

import Foundation
import CryptoKit

extension Storage.Security {
    func encryptWithSoftwareCrypto(_ value: Data) throws -> Data {
        let symmetricKey = try loadOrCreateSoftwareSymmetricKey()
        do {
            let sealedBox = try AES.GCM.seal(value, using: symmetricKey)
            guard let combinedRepresentation = sealedBox.combined else { throw Error.missingCombinedCiphertext }
            return combinedRepresentation
        } catch {
            throw Error.softwareCryptoFailure(error)
        }
    }
    
    func decryptWithSoftwareCrypto(_ value: Data) throws -> Data {
        let symmetricKey = try loadOrCreateSoftwareSymmetricKey()
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: value)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw Error.softwareCryptoFailure(error)
        }
    }
    
    func loadOrCreateSoftwareSymmetricKey() throws -> SymmetricKey {
        if let existing = try copySoftwareSymmetricKeyData() {
            return SymmetricKey(data: existing)
        }
        let newKeyData = try generateSoftwareSymmetricKeyData()
        try storeSoftwareSymmetricKeyData(newKeyData)
        return SymmetricKey(data: newKeyData)
    }
    
    func copySoftwareSymmetricKeyData() throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: softwareKeyIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: keychainAccessibilityAttribute
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
        guard let keyData = output as? Data else { throw Error.secureEnclaveFailure }
        return keyData
    }
    
    func storeSoftwareSymmetricKeyData(_ data: Data) throws {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: softwareKeyIdentifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: keychainAccessibilityAttribute
        ]
        if let accessGroup = options.accessGroup {
            attributes[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: softwareKeyIdentifier
            ]
            if let accessGroup = options.accessGroup {
                query[kSecAttrAccessGroup as String] = accessGroup
            }
            
            let updates: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: keychainAccessibilityAttribute
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else { throw Error.keychainFailure(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw Error.keychainFailure(status) }
    }
    
    func generateSoftwareSymmetricKeyData() throws -> Data {
        var keyData = Data(count: 32)
        let status: Int32 = keyData.withUnsafeMutableBytes { pointer in
            guard let address = pointer.baseAddress else { return errSecMemoryError }
            return SecRandomCopyBytes(kSecRandomDefault, pointer.count, address)
        }
        guard status == errSecSuccess else { throw Error.randomGenerationFailure(status) }
        return keyData
    }
}
