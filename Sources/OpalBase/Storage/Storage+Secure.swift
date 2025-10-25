// Storage+Secure.swift

import Foundation

#if canImport(Security)
import Security
import CryptoKit

extension Storage {
    public struct Secure {
        public struct Options: Sendable {
            public var accessGroup: String?
            public var shouldUseSecureEnclave: Bool
                        public init(accessGroup: String? = nil, shouldUseSecureEnclave: Bool = false) {
                self.accessGroup = accessGroup
                            self.shouldUseSecureEnclave = shouldUseSecureEnclave
            }
        }
        
        private let opts: Options
        private let service = "com.58opals.opal.storage"
        private let cekAccount = "cek.v1"
        
        public init(_ options: Options = .init()) { self.opts = options }
        
        // Store raw or AES.GCM-encrypted with CEK wrapped by Secure Enclave.
        public func store(key: String, value: Data) throws {
            if opts.shouldUseSecureEnclave {
                let cek = try loadOrCreateCEK()
                let sealed = try AES.GCM.seal(value, using: cek)
                guard let combined = sealed.combined else { throw Error.crypto }
                try keychainPut(account: key, data: combined)
            } else {
                try keychainPut(account: key, data: value)
            }
        }
        
        public func retrieve(key: String) throws -> Data? {
            guard let data = try keychainGet(account: key) else { return nil }
            if opts.shouldUseSecureEnclave {
                let cek = try loadOrCreateCEK()
                let box = try AES.GCM.SealedBox(combined: data)
                return try AES.GCM.open(box, using: cek)
            } else {
                return data
            }
        }
        
        public func delete(key: String) throws {
            try keychainDelete(account: key)
        }
        
        public func exists(key: String) -> Bool {
            (try? keychainGet(account: key)) != nil
        }
    }
}

extension Storage.Secure {
    public enum Error: Swift.Error {
        case keychain(OSStatus)
        case crypto
        case enclave
    }
}

extension Storage.Secure {
    func makeKeyAttributes(for account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let g = opts.accessGroup {
            q[kSecAttrAccessGroup as String] = g
        }
        return q
    }

    func keychainPut(account: String, data: Data) throws {
        var q = makeKeyAttributes(for: account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status: OSStatus
        if try keychainGet(account: account) != nil {
            let upd: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(q as CFDictionary, upd as CFDictionary)
        } else {
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Error.keychain(status) }
    }

    func keychainGet(account: String) throws -> Data? {
        var q = makeKeyAttributes(for: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Error.keychain(status) }
        return out as? Data
    }

    func keychainDelete(account: String) throws {
        let q = makeKeyAttributes(for: account)
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.keychain(status) }
    }
}

extension Storage.Secure {
    // CEK is AES 256 stored encrypted with Secure Enclave key.
    func loadOrCreateCEK() throws -> SymmetricKey {
        if let combined = try keychainGet(account: cekAccount) {
            let (wrappedKey, nonce, tag) = try splitWrapped(combined)
            _ = nonce
            _ = tag
            let privKey = try enclaveLoadOrCreateKey()
            let alg = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM
            var error: Unmanaged<CFError>?
            let plaintext = SecKeyCreateDecryptedData(privKey, alg, wrappedKey as CFData, &error) as Data?
            if let plaintext { return SymmetricKey(data: plaintext) }
            throw Error.enclave
        } else {
            let cek = SymmetricKey(size: .bits256)
            let pubKey = try enclaveLoadOrCreatePublicKey()
            let alg = SecKeyAlgorithm.eciesEncryptionCofactorX963SHA256AESGCM
            guard SecKeyIsAlgorithmSupported(pubKey, .encrypt, alg) else { throw Error.enclave }
            var err: Unmanaged<CFError>?
            let wrapped = SecKeyCreateEncryptedData(pubKey, alg, Data(cek.withUnsafeBytes { Data($0) }) as CFData, &err) as Data?
            guard let wrapped else { throw Error.enclave }
            // Store wrapped CEK; nonce/tag unused by ECIES API, add zeros to keep format stable.
            let combined = wrapped + Data(repeating: 0, count: 28)
            try keychainPut(account: cekAccount, data: combined)
            return cek
        }
    }

    func splitWrapped(_ data: Data) throws -> (wrapped: Data, nonce: Data, tag: Data) {
        // Combined = wrapped + 28 zero bytes (placeholder). Backward compatible format.
        if data.count >= 28 { return (data.prefix(data.count - 28), Data(), Data()) }
        return (data, Data(), Data())
    }

    func makeEnclaveKeyTag() -> Data { Data("com.58opals.opal.seckey".utf8) }

    func enclaveLoadOrCreateKey() throws -> SecKey {
        if let key = enclaveCopyKey() { return key }
        var access: SecAccessControl?
        access = SecAccessControlCreateWithFlags(nil,
                                                 kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                                 [.privateKeyUsage],
                                                 nil)
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: makeEnclaveKeyTag(),
                kSecAttrAccessControl as String: access as Any
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else { throw Error.enclave }
        return priv
    }

    func enclaveLoadOrCreatePublicKey() throws -> SecKey {
        let priv = try enclaveLoadOrCreateKey()
        guard let pub = SecKeyCopyPublicKey(priv) else { throw Error.enclave }
        return pub
    }

    func enclaveCopyKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: makeEnclaveKeyTag(),
            kSecReturnRef as String: true
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return (out as! SecKey)
    }
}

#else

extension Storage {
    public struct Secure {
        private var store: [String: Data] = [:]
        public init(service: String) {}
        public mutating func save(_ data: Data, for key: String, useSecureEnclave: Bool = false) throws {
            store[key] = data
        }
        public func read(_ key: String) throws -> Data? { store[key] }
        public mutating func delete(_ key: String) throws { store.removeValue(forKey: key) }
    }
}

#endif
