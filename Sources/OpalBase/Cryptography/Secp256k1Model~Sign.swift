// Secp256k1Model~Sign.swift

import Foundation
import Security

public extension Secp256k1Model {
    static func sign(
        digest32: Data,
        privateKey32: Data,
        nonce: NonceFunctionModel.ECDSA = .rfc6979Sha256,
        enforceLowS: Bool = true
    ) throws -> Signature {
        guard digest32.count == 32 else {
            throw Error.invalidDigestLength(actual: digest32.count)
        }
        guard privateKey32.count == 32 else {
            throw Error.invalidPrivateKeyLength(actual: privateKey32.count)
        }
        let privateKeyScalar: ScalarModel
        do {
            privateKeyScalar = try ScalarModel(data32: privateKey32, requireNonZero: true)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
        let digestScalar = try ScalarConversionModel.makeReducedScalarFromDigest(digest32)
        let makeNextNonce: () throws -> ScalarModel
        switch nonce {
        case .rfc6979Sha256:
            var generator = try NonceGeneratorModel.RFC6979(privateKey: privateKeyScalar, digest32: digest32)
            makeNextNonce = {
                try generator.makeNextScalar()
            }
        case .systemRandom:
            makeNextNonce = {
                try Self.makeSystemRandomScalarForECDSA()
            }
        }
        while true {
            let nonceScalar = try makeNextNonce()
            let noncePoint = ScalarMultiplicationModel.mulG(nonceScalar)
            guard let nonceAffine = noncePoint.convertToAffine() else {
                continue
            }
            guard let signatureRScalar = try? ScalarConversionModel.makeScalarFromFieldElement(nonceAffine.x) else {
                continue
            }
            guard !signatureRScalar.isZero else {
                continue
            }
            let nonceInverse = try nonceScalar.invert()
            let product = signatureRScalar.mulModN(privateKeyScalar)
            let sum = digestScalar.addModN(product)
            var signatureSScalar = nonceInverse.mulModN(sum)
            guard !signatureSScalar.isZero else {
                continue
            }
            if enforceLowS, signatureSScalar.compare(to: halfOrderScalar) == .orderedDescending {
                signatureSScalar = signatureSScalar.negateModN()
            }
            return try Signature(r: signatureRScalar.data32, s: signatureSScalar.data32)
        }
    }
}

private extension Secp256k1Model {
    static func makeSystemRandomScalarForECDSA() throws -> ScalarModel {
        while true {
            var data = Data(count: 32)
            let status = data.withUnsafeMutableBytes { buffer -> Int32 in
                guard let baseAddress = buffer.baseAddress else {
                    return errSecAllocate
                }
                return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
            }
            guard status == errSecSuccess else {
                throw Secp256k1Model.Error.randomGenerationFailed(status: status)
            }
            if let scalar = try? ScalarModel(data32: data, requireNonZero: true) {
                return scalar
            }
        }
    }
}
