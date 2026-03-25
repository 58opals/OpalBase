// SecureEnclaveEnvelope.swift

import Foundation

struct SecureEnclaveEnvelope: Codable, Sendable {
    let version: UInt8
    let salt: Data
    let ephemeralPublicKeyRepresentation: Data
    let combinedCiphertext: Data
}
