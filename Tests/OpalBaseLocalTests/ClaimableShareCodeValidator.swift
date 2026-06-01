// ClaimableShareCodeValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable share code", .tags(.unit))
struct ClaimableShareCodeValidator {
    @Test("round trips all supported networks", arguments: supportedNetworkFixtures)
    func roundTripsAllSupportedNetworks(
        fixture: (network: OpalBase.Network.Environment, token: String, hashByte: UInt8)
    ) throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: fixture.network,
            fundingHashByte: fixture.hashByte
        )

        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        let decodedEnvelope = try OpalBase.Claimable.ShareCode.decode(shareCode)
        let decodedEnvelopeData = try OpalBase.Claimable.ShareCode.decodeEnvelopeData(shareCode)

        #expect(shareCode.hasPrefix("OPALCLAIM:1:\(fixture.token):"))
        #expect(shareCode.allSatisfy(isShareCodeCharacter(_:)))
        #expect(decodedEnvelope == envelope)
        #expect(decodedEnvelopeData == envelope.encode())
    }

    private static let supportedNetworkFixtures: [(
        network: OpalBase.Network.Environment,
        token: String,
        hashByte: UInt8
    )] = [
        (.mainnet, "MAINNET", 0x41),
        (.testnet, "TESTNET", 0x42),
        (.chipnet, "CHIPNET", 0x43)
    ]

    @Test("decodes case-insensitive prefix and network")
    func decodesCaseInsensitivePrefixAndNetwork() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        let mixedCaseShareCode = shareCode.replacingOccurrences(
            of: "OPALCLAIM:1:CHIPNET:",
            with: "opalClaim:1:cHiPnEt:"
        )

        let decodedEnvelope = try OpalBase.Claimable.ShareCode.decode(mixedCaseShareCode)

        #expect(decodedEnvelope == envelope)
    }

    @Test("decodes lowercase base32 payload")
    func decodesLowercaseBase32Payload() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .testnet)
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)

        let decodedEnvelope = try OpalBase.Claimable.ShareCode.decode(shareCode.lowercased())

        #expect(decodedEnvelope == envelope)
    }

    @Test("trims leading and trailing whitespace")
    func trimsLeadingAndTrailingWhitespace() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .testnet)
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)

        let decodedEnvelope = try OpalBase.Claimable.ShareCode.decode("\n  \(shareCode)\t ")

        #expect(decodedEnvelope == envelope)
    }

    @Test("rejects malformed share-code components", arguments: ShareCodeInvalidComponentCase.allCases)
    fileprivate func rejectsMalformedShareCodeComponents(_ invalidCase: ShareCodeInvalidComponentCase) throws {
        let malformedShareCode = try invalidCase.makeShareCode()

        #expect(throws: invalidCase.expectedError) {
            try OpalBase.Claimable.ShareCode.decode(malformedShareCode)
        }
    }

    @Test("rejects envelope network mismatch")
    func rejectsEnvelopeNetworkMismatch() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .mainnet)
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        let mismatchedShareCode = shareCode.replacingOccurrences(
            of: "OPALCLAIM:1:MAINNET:",
            with: "OPALCLAIM:1:TESTNET:"
        )

        #expect(
            throws: OpalBase.Claimable.Error.networkMismatch(
                expected: .testnet,
                actual: .mainnet
            )
        ) {
            try OpalBase.Claimable.ShareCode.decode(mismatchedShareCode)
        }
    }

    enum ShareCodeInvalidComponentCase: CaseIterable, CustomStringConvertible, Sendable {
        case malformedPrefix
        case unsupportedVersion
        case unknownNetwork
        case emptyPayload
        case invalidBase32Characters
        case malformedBase32Length
        case oversizedPayload

        var description: String {
            switch self {
            case .malformedPrefix:
                "malformed prefix"
            case .unsupportedVersion:
                "unsupported version"
            case .unknownNetwork:
                "unknown network"
            case .emptyPayload:
                "empty payload"
            case .invalidBase32Characters:
                "invalid base32 characters"
            case .malformedBase32Length:
                "malformed base32 length"
            case .oversizedPayload:
                "oversized payload"
            }
        }

        var expectedError: OpalBase.Claimable.Error {
            switch self {
            case .malformedPrefix:
                .invalidShareCodeFormat
            case .unsupportedVersion:
                .unsupportedShareCodeVersion("2")
            case .unknownNetwork:
                .invalidShareCodeNetwork("REGTEST")
            case .emptyPayload:
                .emptyShareCodePayload
            case .invalidBase32Characters, .malformedBase32Length, .oversizedPayload:
                .invalidShareCodePayload
            }
        }

        func makeShareCode() throws -> String {
            switch self {
            case .malformedPrefix:
                let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
                let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
                return shareCode.replacingOccurrences(
                    of: "OPALCLAIM:",
                    with: "NOTCLAIM:"
                )
            case .unsupportedVersion:
                return try makeShareCodeReplacingNetworkEnvelope(
                    networkToken: "CHIPNET",
                    replacementNetworkToken: "CHIPNET"
                ).replacingOccurrences(of: "OPALCLAIM:1:", with: "OPALCLAIM:2:")
            case .unknownNetwork:
                return try makeShareCodeReplacingNetworkEnvelope(
                    networkToken: "CHIPNET",
                    replacementNetworkToken: "REGTEST"
                )
            case .emptyPayload:
                return "OPALCLAIM:1:CHIPNET:"
            case .invalidBase32Characters:
                return try makeShareCodeReplacingPayload(with: "ABC0")
            case .malformedBase32Length:
                return try makeShareCodeReplacingPayload(with: "A")
            case .oversizedPayload:
                return try makeShareCodeReplacingPayload(with: String(repeating: "A", count: 165))
            }
        }
    }
}

private func makeShareCodeReplacingNetworkEnvelope(
    networkToken: String,
    replacementNetworkToken: String
) throws -> String {
    let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
    let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
    return shareCode.replacingOccurrences(
        of: "OPALCLAIM:1:\(networkToken):",
        with: "OPALCLAIM:1:\(replacementNetworkToken):"
    )
}

private func makeShareCodeReplacingPayload(with payload: String) throws -> String {
    let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
    let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
    let components = shareCode.split(separator: ":", omittingEmptySubsequences: false)
    return components.prefix(3).joined(separator: ":") + ":\(payload)"
}

private func isShareCodeCharacter(_ character: Character) -> Bool {
    guard let asciiValue = character.asciiValue else { return false }
    return (0x41 ... 0x5a).contains(asciiValue)
        || (0x30 ... 0x39).contains(asciiValue)
        || asciiValue == 0x3a
}
