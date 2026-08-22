// MosaicDeterministicParserMutationCampaign.swift

import Foundation
import Testing

struct MosaicDeterministicParserMutationVector {
    let name: String
    let seedBytes: Data
    let validateAcceptedBytes: (Data) throws -> Bool
}

enum MosaicDeterministicParserMutationCampaign {
    private struct Mutation {
        let name: String
        let bytes: Data
    }

    static func validate(
        _ vectors: [MosaicDeterministicParserMutationVector],
        seed: UInt64,
        seededMutationCount: Int
    ) throws {
        try #require(vectors.isEmpty == false)
        try #require(seededMutationCount > 0)

        for (vectorIndex, vector) in vectors.enumerated() {
            let vectorSeed = seed &+ UInt64(vectorIndex)
            let seedText = String(vectorSeed, radix: 16)
            try #require(vector.seedBytes.isEmpty == false)
            #expect(
                try vector.validateAcceptedBytes(vector.seedBytes),
                "Positive parser seed is unstable: \(vector.name), seed=\(seedText)"
            )

            var rejectedCount = 0
            for mutation in mutations(
                of: vector.seedBytes,
                seed: vectorSeed,
                seededMutationCount: seededMutationCount
            ) where mutation.bytes != vector.seedBytes {
                do {
                    #expect(
                        try vector.validateAcceptedBytes(mutation.bytes),
                        "Accepted bytes were not stable: \(vector.name), seed=\(seedText), mutation=\(mutation.name)"
                    )
                } catch {
                    rejectedCount += 1
                }
            }

            #expect(
                rejectedCount > 0,
                "Mutation campaign did not exercise rejection: \(vector.name), seed=\(seedText)"
            )
        }
    }

    private static func mutations(
        of original: Data,
        seed: UInt64,
        seededMutationCount: Int
    ) -> [Mutation] {
        let bytes = [UInt8](original)
        let lastIndex = bytes.count - 1
        let boundaryOffsets = Array(
            Set([
                0,
                1,
                bytes.count / 4,
                bytes.count / 2,
                bytes.count * 3 / 4,
                lastIndex,
            ])
        )
        .filter { bytes.indices.contains($0) }
        .sorted()
        var result: [Mutation] = boundaryOffsets.map {
            .init(name: "truncate-\($0)", bytes: Data(bytes.prefix($0)))
        }

        for byte in [UInt8(0), UInt8.max] {
            result.append(
                .init(name: "prefix-\(byte)", bytes: Data([byte] + bytes))
            )
            result.append(
                .init(name: "suffix-\(byte)", bytes: Data(bytes + [byte]))
            )
        }
        for index in boundaryOffsets {
            var deleted = bytes
            deleted.remove(at: index)
            result.append(
                .init(name: "delete-\(index)", bytes: Data(deleted))
            )
            for replacement in [
                UInt8(0),
                UInt8(1),
                UInt8(0x7F),
                UInt8(0x80),
                UInt8.max,
            ] {
                var replaced = bytes
                replaced[index] = replacement
                result.append(
                    .init(
                        name: "replace-\(index)-\(replacement)",
                        bytes: Data(replaced)
                    )
                )
            }
        }

        var state = seed
        for iteration in 0..<seededMutationCount {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let index = Int(state % UInt64(bytes.count))
            var mutation = bytes
            mutation[index] ^= UInt8(truncatingIfNeeded: state >> 40) | 1
            result.append(
                .init(
                    name: "seeded-\(iteration)-\(index)",
                    bytes: Data(mutation)
                )
            )
        }
        return result
    }
}

