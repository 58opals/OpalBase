// ClaimableEnvelopeValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable envelope", .tags(.unit))
struct ClaimableEnvelopeValidator {
    @Test("round trips the encoded envelope")
    func roundTripsTheEncodedEnvelope() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
        let encodedEnvelope = envelope.encode()
        let decodedEnvelope = try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)

        #expect(decodedEnvelope == envelope)
    }

    @Test("normalizes sliced claim private key data")
    func normalizesSlicedClaimPrivateKeyData() throws {
        let claimPrivateKey = makeSlicedData(from: ClaimableTestSupport.makeClaimablePrivateKey(lastByte: 0x01))
        let refundPrivateKey = ClaimableTestSupport.makeClaimablePrivateKey(lastByte: 0x02)
        let contract = try OpalBase.Claimable.Contract(
            network: .chipnet,
            claimPublicKeyHash: try makeClaimablePublicKeyHash(
                from: claimPrivateKey,
                invalidError: .invalidClaimPrivateKey
            ),
            refundPublicKeyHash: try makeClaimablePublicKeyHash(
                from: refundPrivateKey,
                invalidError: .invalidRefundPrivateKey
            ),
            expiryBlockHeight: 500
        )

        let envelope = try OpalBase.Claimable.Envelope(
            contract: contract,
            claimPrivateKey: claimPrivateKey,
            fundingTransactionHash: .init(naturalOrder: Data(repeating: 0x44, count: 32)),
            fundingOutputIndex: 1,
            fundingValue: 50_000
        )

        #expect(claimPrivateKey.startIndex != 0)
        #expect(envelope.claimPrivateKey == Data(claimPrivateKey))
        #expect(envelope.claimPrivateKey.startIndex == 0)
    }

    @Test("rejects unsupported version")
    func rejectsUnsupportedVersion() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope[0] = 2

        #expect(throws: OpalBase.Claimable.Error.unsupportedVersion(2)) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("rejects invalid network tag")
    func rejectsInvalidNetworkTag() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope[1] = 9

        #expect(throws: OpalBase.Claimable.Error.invalidNetworkTag(9)) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("rejects network mismatch on decode")
    func rejectsNetworkMismatchOnDecode() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
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
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope.replaceSubrange(26 ..< 58, with: Array(repeating: UInt8(0), count: 32))

        #expect(throws: OpalBase.Claimable.Error.invalidClaimPrivateKey) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("rejects invalid envelope lengths", arguments: InvalidEnvelopeLengthCase.allCases)
    func rejectsInvalidEnvelopeLengths(_ invalidEnvelopeLengthCase: InvalidEnvelopeLengthCase) throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
        let encodedEnvelope = invalidEnvelopeLengthCase.makeEncodedEnvelope(from: envelope)

        #expect(
            throws: OpalBase.Claimable.Error.invalidEnvelopeLength(
                expected: 102,
                actual: invalidEnvelopeLengthCase.actualByteCount
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
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope()
        var encodedEnvelope = envelope.encode()
        encodedEnvelope.replaceSubrange(94 ..< 102, with: invalidFundingValue.littleEndianData)

        #expect(throws: OpalBase.Claimable.Error.invalidFundingOutput) {
            try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope)
        }
    }

    @Test("evaluates local expiry policy")
    func evaluatesLocalExpiryPolicy() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(expiryBlockHeight: 500)
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

    private func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    enum InvalidEnvelopeLengthCase: CaseIterable, Sendable {
        case truncated
        case trailingBytes

        var actualByteCount: Int {
            switch self {
            case .truncated:
                return 101
            case .trailingBytes:
                return 103
            }
        }

        func makeEncodedEnvelope(from envelope: OpalBase.Claimable.Envelope) -> Data {
            switch self {
            case .truncated:
                return Data(envelope.encode().dropLast())
            case .trailingBytes:
                return envelope.encode() + Data([0x00])
            }
        }
    }
}
