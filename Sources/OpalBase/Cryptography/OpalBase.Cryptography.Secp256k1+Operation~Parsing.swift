// OpalBase.Cryptography.Secp256k1+Operation~Parsing.swift

import Foundation

extension OpalBase.Cryptography.Secp256k1.Operation {
    static func parsePrivateKeyScalar(
        _ data: Data,
        requireNonZero: Bool
    ) throws -> ScalarModel {
        do {
            return try ScalarModel(data32: data, requireNonZero: requireNonZero)
        } catch ScalarModel.Error.invalidDataLength(let expected, let actual) {
            precondition(expected == 32)
            throw Error.invalidPrivateKeyLength(actual: actual)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
    }

    static func parsePrivateKeyScalarUnchecked(
        _ data: Data,
        requireNonZero: Bool
    ) throws -> ScalarModel {
        do {
            let parsed = try UInt256Model(data32: data)
            let scalar = ScalarModel(unchecked: parsed)
            guard !requireNonZero || !scalar.isZero else {
                throw ScalarModel.Error.zeroNotAllowed
            }
            return scalar
        } catch UInt256Model.Error.invalidDataLength(let expected, let actual) {
            precondition(expected == 32)
            throw Error.invalidPrivateKeyLength(actual: actual)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
    }

    static func parseTweakScalar(
        _ data: Data,
        requireNonZero: Bool
    ) throws -> ScalarModel {
        do {
            return try ScalarModel(data32: data, requireNonZero: requireNonZero)
        } catch ScalarModel.Error.invalidDataLength(let expected, let actual) {
            precondition(expected == 32)
            throw Error.invalidTweakLength(actual: actual)
        } catch {
            throw Error.invalidTweakValue
        }
    }

    static func parsePublicKeyAffine(_ data: Data) throws -> AffinePointModel {
        do {
            return try OpalBase.PublicKey.ParsingModel.parsePublicKey(data)
        } catch OpalBase.PublicKey.ParsingModel.Error.invalidLength(let actual) {
            throw Error.invalidPublicKeyLength(actual: actual)
        } catch {
            throw Error.invalidPublicKeyValue
        }
    }

    static func encodePublicKey(
        _ affine: AffinePointModel,
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

