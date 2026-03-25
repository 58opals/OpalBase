// SecureEnclaveAdapter.swift

import Foundation
import Security

enum SecureEnclaveAdapter {
    static let envelopeVersion: UInt8 = 1
    static let envelopeContext = Data("OpalBase.Storage.Security.SecureEnclaveEnvelope.v1".utf8)

    static func isRecoverable(_ error: Swift.Error) -> Bool {
        if let securityError = error as? _OpalBase.Storage.Security.Error {
            switch securityError {
            case .protectionUnavailable:
                return true
            case .insufficientProtection:
                return true
            case .encryptionFailure(let underlying), .decryptionFailure(let underlying):
                return isRecoverable(underlying)
            }
        }

        let nsError = error as NSError
        guard nsError.domain == NSOSStatusErrorDomain else { return false }

        switch OSStatus(nsError.code) {
        case errSecNotAvailable, errSecMissingEntitlement, errSecItemNotFound, errSecDecode, errSecParam:
            return true
        default:
            return false
        }
    }
}
