// ClaimableShareCodeValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable share code", .tags(.unit))
struct ClaimableShareCodeValidator {
    @Test("round trips all supported networks")
    func roundTripsAllSupportedNetworks() throws {
        let fixtures: [(network: OpalBase.Network.Environment, token: String, hashByte: UInt8)] = [
            (.mainnet, "MAINNET", 0x41),
            (.testnet, "TESTNET", 0x42),
            (.chipnet, "CHIPNET", 0x43)
        ]

        for fixture in fixtures {
            let (envelope, _) = try makeClaimableEnvelope(
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
    }

    @Test("decodes case-insensitive prefix and network")
    func decodesCaseInsensitivePrefixAndNetwork() throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        let mixedCaseShareCode = shareCode.replacingOccurrences(
            of: "OPALCLAIM:1:CHIPNET:",
            with: "opalClaim:1:cHiPnEt:"
        )

        let decodedEnvelope = try OpalBase.Claimable.ShareCode.decode(mixedCaseShareCode)

        #expect(decodedEnvelope == envelope)
    }

    @Test("trims leading and trailing whitespace")
    func trimsLeadingAndTrailingWhitespace() throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .testnet)
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)

        let decodedEnvelope = try OpalBase.Claimable.ShareCode.decode("\n  \(shareCode)\t ")

        #expect(decodedEnvelope == envelope)
    }

    @Test("rejects malformed prefix")
    func rejectsMalformedPrefix() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        let malformedShareCode = shareCode.replacingOccurrences(
            of: "OPALCLAIM:",
            with: "NOTCLAIM:"
        )

        #expect(throws: OpalBase.Claimable.Error.invalidShareCodeFormat) {
            try OpalBase.Claimable.ShareCode.decode(malformedShareCode)
        }
    }

    @Test("rejects unsupported version")
    func rejectsUnsupportedVersion() throws {
        let malformedShareCode = try makeShareCodeReplacingNetworkEnvelope(
            networkToken: "CHIPNET",
            replacementNetworkToken: "CHIPNET"
        ).replacingOccurrences(of: "OPALCLAIM:1:", with: "OPALCLAIM:2:")

        #expect(throws: OpalBase.Claimable.Error.unsupportedShareCodeVersion("2")) {
            try OpalBase.Claimable.ShareCode.decode(malformedShareCode)
        }
    }

    @Test("rejects unknown network")
    func rejectsUnknownNetwork() throws {
        let malformedShareCode = try makeShareCodeReplacingNetworkEnvelope(
            networkToken: "CHIPNET",
            replacementNetworkToken: "REGTEST"
        )

        #expect(throws: OpalBase.Claimable.Error.invalidShareCodeNetwork("REGTEST")) {
            try OpalBase.Claimable.ShareCode.decode(malformedShareCode)
        }
    }

    @Test("rejects empty payload")
    func rejectsEmptyPayload() {
        #expect(throws: OpalBase.Claimable.Error.emptyShareCodePayload) {
            try OpalBase.Claimable.ShareCode.decode("OPALCLAIM:1:CHIPNET:")
        }
    }

    @Test("rejects invalid base32 characters")
    func rejectsInvalidBase32Characters() throws {
        let malformedShareCode = try makeShareCodeReplacingPayload(with: "ABC0")

        #expect(throws: OpalBase.Claimable.Error.invalidShareCodePayload) {
            try OpalBase.Claimable.ShareCode.decode(malformedShareCode)
        }
    }

    @Test("rejects malformed base32 length")
    func rejectsMalformedBase32Length() throws {
        let malformedShareCode = try makeShareCodeReplacingPayload(with: "A")

        #expect(throws: OpalBase.Claimable.Error.invalidShareCodePayload) {
            try OpalBase.Claimable.ShareCode.decode(malformedShareCode)
        }
    }

    @Test("rejects envelope network mismatch")
    func rejectsEnvelopeNetworkMismatch() throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .mainnet)
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
}

private func makeShareCodeReplacingNetworkEnvelope(
    networkToken: String,
    replacementNetworkToken: String
) throws -> String {
    let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
    let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
    return shareCode.replacingOccurrences(
        of: "OPALCLAIM:1:\(networkToken):",
        with: "OPALCLAIM:1:\(replacementNetworkToken):"
    )
}

private func makeShareCodeReplacingPayload(with payload: String) throws -> String {
    let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
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
