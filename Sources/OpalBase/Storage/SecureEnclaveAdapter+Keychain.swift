// SecureEnclaveAdapter+Keychain.swift

import CryptoKit
import Foundation
import Security

extension SecureEnclaveAdapter {
    static func prepare(applicationTag: Data) throws {
        _ = try loadOrCreatePrivateKey(applicationTag: applicationTag)
    }

    static func deleteKey(applicationTag: Data) throws {
        let status = SecItemDelete(keyQuery(applicationTag: applicationTag, returnReference: false) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw makeSecurityError(status: status, message: "Failed to delete the Secure Enclave key.")
        }
    }

    static func loadOrCreatePrivateKey(applicationTag: Data) throws -> SecKey {
        if let privateKey = try findPrivateKey(applicationTag: applicationTag) {
            return privateKey
        }

        guard SecureEnclave.isAvailable else {
            throw _OpalBase.Storage.Security.Error.protectionUnavailable
        }

        do {
            try createPrivateKey(applicationTag: applicationTag)
        } catch {
            if securityStatus(from: error) != errSecDuplicateItem {
                throw error
            }
        }

        guard let privateKey = try findPrivateKey(applicationTag: applicationTag) else {
            throw _OpalBase.Storage.Security.Error.protectionUnavailable
        }

        return privateKey
    }

    static func loadPrivateKey(applicationTag: Data) throws -> SecKey {
        guard let privateKey = try findPrivateKey(applicationTag: applicationTag) else {
            throw makeSecurityError(
                status: errSecItemNotFound,
                message: "Secure Enclave key material is unavailable for decryption."
            )
        }

        return privateKey
    }

    static func createPrivateKey(applicationTag: Data) throws {
        let accessControl = try makeAccessControl()
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrAccessControl as String: accessControl,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            if let error {
                throw normalizeProtectionAvailabilityError(error.takeRetainedValue() as Swift.Error)
            }

            throw _OpalBase.Storage.Security.Error.protectionUnavailable
        }
    }

    static func findPrivateKey(applicationTag: Data) throws -> SecKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            keyQuery(applicationTag: applicationTag, returnReference: true) as CFDictionary,
            &item
        )

        switch status {
        case errSecSuccess:
            guard let item, CFGetTypeID(item) == SecKeyGetTypeID() else {
                throw makeSecurityError(
                    status: errSecDecode,
                    message: "Secure Enclave key lookup returned an unexpected object."
                )
            }
            return (item as! SecKey)
        case errSecItemNotFound:
            return nil
        default:
            throw normalizeProtectionAvailabilityError(
                makeSecurityError(status: status, message: "Failed to look up the Secure Enclave key.")
            )
        }
    }

    static func keyQuery(applicationTag: Data, returnReference: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        ]

        if returnReference {
            query[kSecReturnRef as String] = true
        }

        return query
    }

    static func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence, .privateKeyUsage],
            &error
        ) else {
            if let error {
                throw error.takeRetainedValue() as Swift.Error
            }

            throw _OpalBase.Storage.Security.Error.protectionUnavailable
        }

        return accessControl
    }

    static func securityStatus(from error: Swift.Error) -> OSStatus? {
        let nsError = error as NSError
        guard nsError.domain == NSOSStatusErrorDomain else { return nil }
        return OSStatus(nsError.code)
    }

    static func normalizeProtectionAvailabilityError(_ error: Swift.Error) -> Swift.Error {
        guard let status = securityStatus(from: error) else { return error }

        switch status {
        case errSecNotAvailable, errSecMissingEntitlement:
            return _OpalBase.Storage.Security.Error.protectionUnavailable
        default:
            return error
        }
    }

    static func makeSecurityError(status: OSStatus, message: String) -> NSError {
        let statusText = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Security.framework error."
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSDebugDescriptionErrorKey: message + " " + statusText]
        )
    }
}
