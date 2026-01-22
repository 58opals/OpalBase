// NonceGenerator+RFC6979.swift

import Foundation
import CryptoKit

extension NonceGenerator {
    struct RFC6979 {
        private var keyBytes: Data
        private var valueBytes: Data
        private let privateKeyData: Data
        private let digestData: Data
        
        init(privateKey: Scalar, digest32: Data) throws {
            guard digest32.count == 32 else {
                throw Secp256k1.Error.invalidDigestLength(actual: digest32.count)
            }
            privateKeyData = privateKey.data32
            digestData = try ScalarConversion.makeReducedDataFromDigest(digest32)
            valueBytes = Data(repeating: 0x01, count: 32)
            keyBytes = Data(repeating: 0x00, count: 32)
            updateKeyAndValue(separator: 0x00, includeKeyMaterial: true)
            updateKeyAndValue(separator: 0x01, includeKeyMaterial: true)
        }
        
        mutating func makeNextScalar() throws -> Scalar {
            while true {
                valueBytes = makeAuthenticationCode(key: keyBytes, message: valueBytes)
                let candidateBytes = valueBytes
                let candidateScalar = try? Scalar(data32: candidateBytes, requireNonZero: true)
                updateKeyAndValue(separator: 0x00, includeKeyMaterial: false)
                if let scalar = candidateScalar {
                    return scalar
                }
            }
        }
        
        private mutating func updateKeyAndValue(separator: UInt8, includeKeyMaterial: Bool) {
            var material = Data()
            material.append(valueBytes)
            material.append(separator)
            if includeKeyMaterial {
                material.append(privateKeyData)
                material.append(digestData)
            }
            keyBytes = makeAuthenticationCode(key: keyBytes, message: material)
            valueBytes = makeAuthenticationCode(key: keyBytes, message: valueBytes)
        }
    }
}

private func makeAuthenticationCode(key: Data, message: Data) -> Data {
    let keyValue = SymmetricKey(data: key)
    let authenticationCode = HMAC<CryptoKit.SHA256>.authenticationCode(for: message, using: keyValue)
    return Data(authenticationCode)
}
