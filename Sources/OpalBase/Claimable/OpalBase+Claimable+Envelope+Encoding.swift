// OpalBase+Claimable+Envelope+Encoding.swift

import Foundation
import OpalDiagnostics

extension _OpalBase.Claimable.Envelope {
    private static let version: UInt8 = 1
    static let encodedByteCount = 102

    public func encode() -> Data {
        OpalDiagnostics.withTraceID {
            var writer = Data.Writer()
            writer.reserveCapacity(Self.encodedByteCount)
            writer.writeByte(Self.version)
            writer.writeByte(Self.makeNetworkTag(for: contract.network))
            writer.writeLittleEndian(contract.expiryBlockHeight)
            writer.writeData(contract.refundPublicKeyHash)
            writer.writeData(claimPrivateKey)
            writer.writeData(fundingTransactionHash.naturalOrder)
            writer.writeLittleEndian(fundingOutputIndex)
            writer.writeLittleEndian(fundingValue)
            let encodedEnvelopeData = writer.data
            OpalDiagnostics.record(
                OpalDiagnostics.Event.claimableEnvelopeEncoded,
                category: OpalDiagnostics.Category.claimable,
                fields: [
                    OpalDiagnostics.Field.operation("claimable_envelope_encode"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.network(contract.network),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.byteCount, encodedEnvelopeData.count)
                ]
            )
            return encodedEnvelopeData
        }
    }

    public static func decode(from data: Data) throws -> Self {
        try decodeEnvelopeWithDiagnostics(from: data, expectedNetwork: nil)
    }

    public static func decode(
        from data: Data,
        on network: OpalBase.Network.Environment
    ) throws -> Self {
        try decodeEnvelopeWithDiagnostics(from: data, expectedNetwork: network)
    }

    private static func decodeEnvelopeWithDiagnostics(
        from data: Data,
        expectedNetwork: OpalBase.Network.Environment?
    ) throws -> Self {
        try OpalDiagnostics.withTraceID {
            let fields = makeDecodeDiagnosticsFields(
                byteCount: data.count,
                network: expectedNetwork
            )
            do {
                let envelope = try decodeEnvelope(from: data)
                if let expectedNetwork {
                    guard envelope.contract.network == expectedNetwork else {
                        throw OpalBase.Claimable.Error.networkMismatch(
                            expected: expectedNetwork,
                            actual: envelope.contract.network
                        )
                    }
                }
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.claimableEnvelopeDecodeSucceeded,
                    category: OpalDiagnostics.Category.claimable,
                    fields: makeDecodeDiagnosticsFields(
                        byteCount: data.count,
                        network: expectedNetwork ?? envelope.contract.network
                    )
                )
                return envelope
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.claimableEnvelopeDecodeFailed,
                    category: OpalDiagnostics.Category.claimable,
                    fields: fields + OpalDiagnostics.Field.errorFields(
                        for: error,
                        fallback: OpalDiagnostics.ErrorCode.claimableInvalidEnvelope
                    )
                )
                throw error
            }
        }
    }

    private static func decodeEnvelope(from data: Data) throws -> Self {
        guard data.count == Self.encodedByteCount else {
            throw OpalBase.Claimable.Error.invalidEnvelopeLength(
                expected: Self.encodedByteCount,
                actual: data.count
            )
        }

        var reader = Data.Reader(data)

        let version: UInt8 = try reader.readLittleEndian()
        guard version == Self.version else {
            throw OpalBase.Claimable.Error.unsupportedVersion(version)
        }

        let networkTag: UInt8 = try reader.readLittleEndian()
        let network = try Self.makeNetwork(from: networkTag)
        let expiryBlockHeight: UInt32 = try reader.readLittleEndian()
        let refundPublicKeyHash = try reader.readData(count: 20)
        let claimPrivateKey = try reader.readData(count: 32)
        let fundingTransactionHashData = try reader.readData(count: 32)
        let fundingOutputIndex: UInt32 = try reader.readLittleEndian()
        let fundingValue: UInt64 = try reader.readLittleEndian()

        let claimPublicKeyHash = try ClaimablePrimitiveOperation.makePublicKeyHash(
            from: claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        let contract = try OpalBase.Claimable.Contract(
            network: network,
            claimPublicKeyHash: claimPublicKeyHash,
            refundPublicKeyHash: refundPublicKeyHash,
            expiryBlockHeight: expiryBlockHeight
        )

        return try Self(
            contract: contract,
            claimPrivateKey: claimPrivateKey,
            fundingTransactionHash: .init(naturalOrder: fundingTransactionHashData),
            fundingOutputIndex: fundingOutputIndex,
            fundingValue: fundingValue
        )
    }

    private static func makeDecodeDiagnosticsFields(
        byteCount: Int,
        network: OpalBase.Network.Environment? = nil
    ) -> [OpalDiagnostics.Field] {
        [
            OpalDiagnostics.Field.operation("claimable_envelope_decode"),
            OpalDiagnostics.Field.module(),
            network.map(OpalDiagnostics.Field.network),
            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.byteCount, byteCount)
        ].compactMap { $0 }
    }

    private static func makeNetworkTag(for network: OpalBase.Network.Environment) -> UInt8 {
        switch network {
        case .mainnet:
            return 0
        case .chipnet:
            return 1
        case .testnet:
            return 2
        }
    }

    private static func makeNetwork(from networkTag: UInt8) throws -> OpalBase.Network.Environment {
        switch networkTag {
        case 0:
            return .mainnet
        case 1:
            return .chipnet
        case 2:
            return .testnet
        default:
            throw OpalBase.Claimable.Error.invalidNetworkTag(networkTag)
        }
    }
}
