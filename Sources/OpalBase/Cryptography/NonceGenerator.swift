// NonceGenerator.swift

import Foundation
import CryptoKit
import Security

struct NonceGenerator {
    private var keyBytes: Data
    private var valueBytes: Data
    private let additionalData: Data
    private let privateKeyData: Data
    private let digestData: Data
    
    init(privateKey: Scalar, digest32: Data) throws {
        guard digest32.count == 32 else {
            throw ChallengeHash.Error.invalidDigestLength(actual: digest32.count)
        }
        additionalData = Data("Schnorr+SHA256  ".utf8)
        privateKeyData = privateKey.data32
        digestData = digest32
        valueBytes = Data(repeating: 0x01, count: 32)
        keyBytes = Data(repeating: 0x00, count: 32)
        updateKeyAndValue(isSecondRound: false)
        updateKeyAndValue(isSecondRound: true)
    }
    
    mutating func makeNextScalar() throws -> Scalar {
        while true {
            valueBytes = makeAuthenticationCode(key: keyBytes, message: valueBytes)
            if let scalar = try? Scalar(data32: valueBytes, requireNonZero: true) {
                return scalar
            }
            var material = Data()
            material.append(valueBytes)
            material.append(0x00)
            keyBytes = makeAuthenticationCode(key: keyBytes, message: material)
            valueBytes = makeAuthenticationCode(key: keyBytes, message: valueBytes)
        }
    }
    
    private mutating func updateKeyAndValue(isSecondRound: Bool) {
        var material = Data()
        material.append(valueBytes)
        material.append(isSecondRound ? 0x01 : 0x00)
        material.append(privateKeyData)
        material.append(digestData)
        material.append(additionalData)
        keyBytes = makeAuthenticationCode(key: keyBytes, message: material)
        valueBytes = makeAuthenticationCode(key: keyBytes, message: valueBytes)
    }
}

func makeSystemRandomScalar() throws -> Scalar {
    while true {
        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                return errSecAllocate
            }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }
        guard status == errSecSuccess else {
            throw Schnorr.Error.randomGenerationFailed(status: status)
        }
        if let scalar = try? Scalar(data32: data, requireNonZero: true) {
            return scalar
        }
    }
}

private func makeAuthenticationCode(key: Data, message: Data) -> Data {
    let keyValue = SymmetricKey(data: key)
    let authenticationCode = HMAC<CryptoKit.SHA256>.authenticationCode(for: message, using: keyValue)
    return Data(authenticationCode)
}
