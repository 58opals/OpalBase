// Secp256k1Model+OperationModel+CompressedPublicKeyChunkResultModel.swift

import Foundation

extension Secp256k1Model.OperationModel {
    static func deriveCompressedPublicKeys(
        fromPrivateKeys32 privateKeys32: [Data],
        assumingValidPrivateKeys: Bool = false
    ) async throws -> [Data] {
        guard !privateKeys32.isEmpty else { return .init() }

        let maximumChunkSize = 256
        let totalCount = privateKeys32.count
        if totalCount <= 64 {
            return try deriveCompressedPublicKeysSingleChunk(
                fromPrivateKeys32: privateKeys32,
                assumingValidPrivateKeys: assumingValidPrivateKeys
            )
        }
        let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let taskCount = min(processorCount, totalCount)
        let idealChunkSize = (totalCount + taskCount - 1) / taskCount
        let chunkSize = min(maximumChunkSize, max(1, idealChunkSize))
        let chunkCount = (totalCount + chunkSize - 1) / chunkSize

        return try await withThrowingTaskGroup(of: CompressedPublicKeyChunkResultModel.self) { group in
            for chunkIndex in 0..<chunkCount {
                let startIndex = chunkIndex * chunkSize
                let endIndex = min(startIndex + chunkSize, totalCount)
                let privateKeySlice = privateKeys32[startIndex..<endIndex]

                group.addTask {
                    var jacobianPoints: [JacobianPointModel] = .init()
                    jacobianPoints.reserveCapacity(privateKeySlice.count)

                    for privateKey32 in privateKeySlice {
                        let privateKeyScalar = assumingValidPrivateKeys
                        ? try self.parsePrivateKeyScalarUnchecked(privateKey32, requireNonZero: true)
                        : try self.parsePrivateKeyScalar(privateKey32, requireNonZero: true)
                        jacobianPoints.append(ScalarMultiplicationModel.mulG(privateKeyScalar))
                    }

                    let affinePoints = JacobianPointModel.convertBatchToAffine(jacobianPoints)
                    var compressedPublicKeys: [Data] = .init()
                    compressedPublicKeys.reserveCapacity(affinePoints.count)

                    for affinePoint in affinePoints {
                        guard let affinePoint else {
                            throw Error.invalidDerivedPublicKey
                        }
                        compressedPublicKeys.append(affinePoint.encodeCompressed33())
                    }

                    return CompressedPublicKeyChunkResultModel(
                        startIndex: startIndex,
                        compressedPublicKeys: compressedPublicKeys
                    )
                }
            }

            var chunkResults: [CompressedPublicKeyChunkResultModel] = .init()
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
}

private extension Secp256k1Model.OperationModel {
    struct CompressedPublicKeyChunkResultModel: Sendable {
        let startIndex: Int
        let compressedPublicKeys: [Data]
    }

    static func deriveCompressedPublicKeysSingleChunk(
        fromPrivateKeys32 privateKeys32: [Data],
        assumingValidPrivateKeys: Bool
    ) throws -> [Data] {
        var jacobianPoints: [JacobianPointModel] = .init()
        jacobianPoints.reserveCapacity(privateKeys32.count)

        for privateKey32 in privateKeys32 {
            let privateKeyScalar = assumingValidPrivateKeys
            ? try self.parsePrivateKeyScalarUnchecked(privateKey32, requireNonZero: true)
            : try self.parsePrivateKeyScalar(privateKey32, requireNonZero: true)
            jacobianPoints.append(ScalarMultiplicationModel.mulG(privateKeyScalar))
        }

        let affinePoints = JacobianPointModel.convertBatchToAffine(jacobianPoints)
        var compressedPublicKeys: [Data] = .init()
        compressedPublicKeys.reserveCapacity(affinePoints.count)

        for affinePoint in affinePoints {
            guard let affinePoint else {
                throw Error.invalidDerivedPublicKey
            }
            compressedPublicKeys.append(encodePublicKey(affinePoint, format: .compressed))
        }

        return compressedPublicKeys
    }
}

