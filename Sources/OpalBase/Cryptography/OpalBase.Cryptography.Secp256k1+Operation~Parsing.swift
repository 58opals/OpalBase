// OpalBase.Cryptography.Secp256k1+Operation~Parsing.swift

import Foundation

extension OpalBase.Cryptography.Secp256k1.Operation {
    static func parsePrivateKeyScalar(
        _ data: Data,
        requireNonZero: Bool
    ) throws -> Scalar {
        do {
            return try Scalar(data32: data, requireNonZero: requireNonZero)
        } catch Scalar.Error.invalidDataLength(let expected, let actual) {
            precondition(expected == 32)
            throw Error.invalidPrivateKeyLength(actual: actual)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
    }

    static func parsePrivateKeyScalarUnchecked(
        _ data: Data,
        requireNonZero: Bool
    ) throws -> Scalar {
        do {
            let parsed = try UInt256(data32: data)
            let scalar = Scalar(unchecked: parsed)
            guard !requireNonZero || !scalar.isZero else {
                throw Scalar.Error.zeroNotAllowed
            }
            return scalar
        } catch UInt256.Error.invalidDataLength(let expected, let actual) {
            precondition(expected == 32)
            throw Error.invalidPrivateKeyLength(actual: actual)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
    }

    static func parseTweakScalar(
        _ data: Data,
        requireNonZero: Bool
    ) throws -> Scalar {
        do {
            return try Scalar(data32: data, requireNonZero: requireNonZero)
        } catch Scalar.Error.invalidDataLength(let expected, let actual) {
            precondition(expected == 32)
            throw Error.invalidTweakLength(actual: actual)
        } catch {
            throw Error.invalidTweakValue
        }
    }

    static func parsePublicKeyAffine(_ data: Data) throws -> AffinePoint {
        do {
            return try OpalBase.PublicKey.Parsing.parsePublicKey(data)
        } catch OpalBase.PublicKey.Parsing.Error.invalidLength(let actual) {
            throw Error.invalidPublicKeyLength(actual: actual)
        } catch {
            throw Error.invalidPublicKeyValue
        }
    }

    static func encodePublicKey(
        _ affine: AffinePoint,
        format: PublicKeyFormat
    ) -> Data {
        switch format {
        case .compressed:
            return affine.encodeCompressed33()
        case .uncompressed:
            return affine.encodeUncompressed65()
        }
    }

    static func resolveFormat(
        from publicKey: Data,
        format: PublicKeyFormat?
    ) throws -> PublicKeyFormat {
        if let format {
            return format
        }
        switch publicKey.count {
        case 33:
            return .compressed
        case 65:
            return .uncompressed
        default:
            throw Error.invalidPublicKeyLength(actual: publicKey.count)
        }
    }
}

