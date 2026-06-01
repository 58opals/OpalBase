// SecureEnclaveEnvelope.swift

import Foundation

struct SecureEnclaveEnvelope: Codable, Sendable {
    let version: UInt8
    let salt: Data
    let ephemeralPublicKeyRepresentation: Data
    let combinedCiphertext: Data

    init(
        version: UInt8,
        salt: Data,
        ephemeralPublicKeyRepresentation: Data,
        combinedCiphertext: Data
    ) {
        self.version = version
        self.salt = Data(salt)
        self.ephemeralPublicKeyRepresentation = Data(ephemeralPublicKeyRepresentation)
        self.combinedCiphertext = Data(combinedCiphertext)
    }
}
