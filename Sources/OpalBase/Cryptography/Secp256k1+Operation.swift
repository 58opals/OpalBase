// Secp256k1+Operation.swift

import Foundation

extension Secp256k1 {
    public enum Operation {
        public enum PublicKeyFormat {
            case compressed
            case uncompressed
        }
        
        public enum Error: Swift.Error, Equatable {
            case invalidPrivateKeyLength(actual: Int)
            case invalidPrivateKeyValue
            case invalidPublicKeyLength(actual: Int)
            case invalidPublicKeyValue
            case invalidTweakLength(actual: Int)
            case invalidTweakValue
            case invalidDerivedPrivateKey
            case invalidDerivedPublicKey
        }
        
        public static var curveOrderN: Data {
            Secp256k1.Constant.n.data32
        }
        
        public static func isValidPrivateKey32(_ privateKey32: Data) -> Bool {
            (try? Scalar(data32: privateKey32, requireNonZero: true)) != nil
        }
        
        public static func publicKey(
            fromPrivateKey32 privateKey32: Data,
            format: PublicKeyFormat = .compressed
        ) throws -> Data {
            let privateKeyScalar = try parsePrivateKeyScalar(privateKey32, requireNonZero: true)
            let publicPoint = ScalarMultiplication.mulG(privateKeyScalar)
            guard let publicAffine = publicPoint.toAffine() else {
                throw Error.invalidDerivedPublicKey
            }
            return encodePublicKey(publicAffine, format: format)
        }
        
        static func deriveCompressedPublicKeys(
            fromPrivateKeys32 privateKeys32: [Data]
        ) async throws -> [Data] {
            guard !privateKeys32.isEmpty else { return .init() }
            
            let maximumChunkSize = 256
            let totalCount = privateKeys32.count
            if totalCount <= 64 {
                return try deriveCompressedPublicKeysSingleChunk(fromPrivateKeys32: privateKeys32)
            }
            let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let taskCount = min(processorCount, totalCount)
            let idealChunkSize = (totalCount + taskCount - 1) / taskCount
            let chunkSize = min(maximumChunkSize, max(1, idealChunkSize))
            let chunkCount = (totalCount + chunkSize - 1) / chunkSize
            
            return try await withThrowingTaskGroup(of: CompressedPublicKeyChunkResult.self) { group in
                for chunkIndex in 0..<chunkCount {
                    let startIndex = chunkIndex * chunkSize
                    let endIndex = min(startIndex + chunkSize, totalCount)
                    let privateKeySlice = privateKeys32[startIndex..<endIndex]
                    
                    group.addTask {
                        var jacobianPoints: [JacobianPoint] = .init()
                        jacobianPoints.reserveCapacity(privateKeySlice.count)
                        
                        for privateKey32 in privateKeySlice {
                            let privateKeyScalar = try parsePrivateKeyScalar(privateKey32, requireNonZero: true)
                            jacobianPoints.append(ScalarMultiplication.mulG(privateKeyScalar))
                        }
                        
                        let affinePoints = JacobianPoint.batchToAffine(jacobianPoints)
                        var compressedPublicKeys: [Data] = .init()
                        compressedPublicKeys.reserveCapacity(affinePoints.count)
                        
                        for affinePoint in affinePoints {
                            guard let affinePoint else {
                                throw Error.invalidDerivedPublicKey
                            }
                            compressedPublicKeys.append(affinePoint.compressedEncoding33())
                        }
                        
                        return CompressedPublicKeyChunkResult(
                            startIndex: startIndex,
                            compressedPublicKeys: compressedPublicKeys
                        )
                    }
                }
                
                var chunkResults: [CompressedPublicKeyChunkResult] = .init()
                chunkResults.reserveCapacity(chunkCount)
                
                for try await chunkResult in group {
                    chunkResults.append(chunkResult)
                }
                
                chunkResults.sort { $0.startIndex < $1.startIndex }
                
                var compressedPublicKeys: [Data] = .init()
                compressedPublicKeys.reserveCapacity(totalCount)
                for chunkResult in chunkResults {
                    compressedPublicKeys.append(contentsOf: chunkResult.compressedPublicKeys)
                }
                return compressedPublicKeys
            }
        }
        
        public static func tweakAddPrivateKey32(
            _ privateKey32: Data,
            tweak32: Data
        ) throws -> Data {
            let privateKeyScalar = try parsePrivateKeyScalar(privateKey32, requireNonZero: true)
            let tweakScalar = try parseTweakScalar(tweak32, requireNonZero: false)
            let derivedScalar = privateKeyScalar.addModN(tweakScalar)
            guard !derivedScalar.isZero else {
                throw Error.invalidDerivedPrivateKey
            }
            return derivedScalar.data32
        }
        
        public static func tweakAddPublicKey(
            _ publicKey: Data,
            tweak32: Data,
            format: PublicKeyFormat? = nil
        ) throws -> Data {
            let publicAffine = try parsePublicKeyAffine(publicKey)
            let tweakScalar = try parseTweakScalar(tweak32, requireNonZero: true)
            let tweakPoint = ScalarMultiplication.mulG(tweakScalar)
            let combined = JacobianPoint(affine: publicAffine).add(tweakPoint)
            guard let derivedAffine = combined.toAffine() else {
                throw Error.invalidDerivedPublicKey
            }
            let resolvedFormat = try resolveFormat(from: publicKey, format: format)
            return encodePublicKey(derivedAffine, format: resolvedFormat)
        }
    }
}

private extension Secp256k1.Operation {
    struct CompressedPublicKeyChunkResult: Sendable {
        let startIndex: Int
        let compressedPublicKeys: [Data]
    }
    
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
    
    static func deriveCompressedPublicKeysSingleChunk(
        fromPrivateKeys32 privateKeys32: [Data]
    ) throws -> [Data] {
        var jacobianPoints: [JacobianPoint] = []
        jacobianPoints.reserveCapacity(privateKeys32.count)
        
        for privateKey32 in privateKeys32 {
            let privateKeyScalar = try parsePrivateKeyScalar(privateKey32, requireNonZero: true)
            jacobianPoints.append(ScalarMultiplication.mulG(privateKeyScalar))
        }
        
        let affinePoints = JacobianPoint.batchToAffine(jacobianPoints)
        var compressedPublicKeys: [Data] = []
        compressedPublicKeys.reserveCapacity(affinePoints.count)
        
        for affinePoint in affinePoints {
            guard let affinePoint else {
                throw Error.invalidDerivedPublicKey
            }
            compressedPublicKeys.append(encodePublicKey(affinePoint, format: .compressed))
        }
        
        return compressedPublicKeys
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
            return try PublicKey.Parsing.parsePublicKey(data)
        } catch PublicKey.Parsing.Error.invalidLength(let actual) {
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
            return affine.compressedEncoding33()
        case .uncompressed:
            return affine.uncompressedEncoding65()
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
