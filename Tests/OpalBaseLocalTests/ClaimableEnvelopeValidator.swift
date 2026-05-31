// ClaimableEnvelopeValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable envelope", .tags(.unit))
struct ClaimableEnvelopeValidator {
    @Test("round trips the encoded envelope")
    func roundTripsTheEncodedEnvelope() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        let encodedEnvelope = envelope.encode()
        let decodedEnvelope = try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)

        #expect(decodedEnvelope == envelope)
    }

    @Test("rejects unsupported version")
    func rejectsUnsupportedVersion() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope[0] = 2

        #expect(throws: OpalBase.Claimable.Error.unsupportedVersion(2)) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("rejects invalid network tag")
    func rejectsInvalidNetworkTag() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope[1] = 9

        #expect(throws: OpalBase.Claimable.Error.invalidNetworkTag(9)) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("rejects network mismatch on decode")
    func rejectsNetworkMismatchOnDecode() throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
        let encodedEnvelope = envelope.encode()

        #expect(
            throws: OpalBase.Claimable.Error.networkMismatch(
                expected: .mainnet,
                actual: .chipnet
            )
        ) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope, on: .mainnet)
        }
    }

    @Test("rejects invalid claim private key payload")
    func rejectsInvalidClaimPrivateKeyPayload() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope.replaceSubrange(26 ..< 58, with: Array(repeating: UInt8(0), count: 32))

        #expect(throws: OpalBase.Claimable.Error.invalidClaimPrivateKey) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("rejects truncated envelope payload")
    func rejectsTruncatedEnvelopePayload() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        let encodedEnvelope = envelope.encode().dropLast()

        #expect(
            throws: OpalBase.Claimable.Error.invalidEnvelopeLength(
                expected: 102,
                actual: 101
            )
        ) {
            try OpalBase.Claimable.Envelope.decode(from: Data(encodedEnvelope))
        }
    }

    @Test("rejects trailing envelope bytes")
    func rejectsTrailingEnvelopeBytes() throws {
        let (envelope, _) = try makeClaimableEnvelope()
        let encodedEnvelope = envelope.encode() + Data([0x00])

        #expect(
            throws: OpalBase.Claimable.Error.invalidEnvelopeLength(
                expected: 102,
                actual: 103
            )
        ) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test(
        "rejects invalid funding values",
        arguments: [UInt64(0), OpalBase.Satoshi.maximumSatoshi + 1]
    )
    func rejectsInvalidFundingValues(_ invalidFundingValue: UInt64) throws {
        let (envelope, _) = try makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope.replaceSubrange(94 ..< 102, with: invalidFundingValue.littleEndianData)

        #expect(throws: OpalBase.Claimable.Error.invalidFundingOutput) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("evaluates local expiry policy")
    func evaluatesLocalExpiryPolicy() throws {
        let (envelope, _) = try makeClaimableEnvelope(expiryBlockHeight: 500)
        let beforeExpiry = envelope.makeLocalStatus(currentBlockHeight: 499)
        let atExpiry = envelope.makeLocalStatus(currentBlockHeight: 500)
        let afterExpiry = envelope.makeLocalStatus(currentBlockHeight: 700)

        #expect(beforeExpiry.isExpired == false)
        #expect(beforeExpiry.allowsClaim)
        #expect(beforeExpiry.allowsRefund == false)

        #expect(atExpiry.isExpired)
        #expect(atExpiry.allowsClaim == false)
        #expect(atExpiry.allowsRefund)

        #expect(afterExpiry.isExpired)
        #expect(afterExpiry.allowsClaim == false)
        #expect(afterExpiry.allowsRefund)
    }
}
