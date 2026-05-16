// OpalBase+Claimable+Envelope~Encoding.swift

import Foundation

extension _OpalBase.Claimable.Envelope {
    private static let version: UInt8 = 1
    private static let encodedByteCount = 102

    public func encode() -> Data {
        OpalBase.Diagnostics.withTraceID {
            var writer = Data.Writer()
            writer.reserveCapacity(Self.encodedByteCount)
            writer.writeByte(Self.version)
            writer.writeByte(makeClaimableNetworkTag(for: contract.network))
            writer.writeLittleEndian(contract.expiryBlockHeight)
            writer.writeData(contract.refundPublicKeyHash)
            writer.writeData(claimPrivateKey)
            writer.writeData(fundingTransactionHash.naturalOrder)
            writer.writeLittleEndian(fundingOutputIndex)
            writer.writeLittleEndian(fundingValue)
            let data = writer.data
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.claimableEnvelopeEncoded,
                category: OpalBase.Diagnostics.Categories.claimable,
                fields: [
                    OpalBaseDiagnostics.operationField("claimable_envelope_encode"),
                    OpalBaseDiagnostics.moduleField(),
                    OpalBaseDiagnostics.networkField(contract.network),
                    OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.byteCount, data.count)
                ]
            )
            return data
        }
    }

    public static func decode(from data: Data) throws -> Self {
        try OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("claimable_envelope_decode"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.byteCount, data.count)
            ]
            do {
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
                let network = try makeClaimableNetwork(from: networkTag)
                let expiryBlockHeight: UInt32 = try reader.readLittleEndian()
                let refundPublicKeyHash = try reader.readData(count: 20)
                let claimPrivateKey = try reader.readData(count: 32)
                let fundingTransactionHashData = try reader.readData(count: 32)
                let fundingOutputIndex: UInt32 = try reader.readLittleEndian()
                let fundingValue: UInt64 = try reader.readLittleEndian()

                let claimPublicKeyHash = try makeClaimablePublicKeyHash(
                    from: claimPrivateKey,
                    invalidError: .invalidClaimPrivateKey
                )
                let contract = try OpalBase.Claimable.Contract(
                    network: network,
                    claimPublicKeyHash: claimPublicKeyHash,
                    refundPublicKeyHash: refundPublicKeyHash,
                    expiryBlockHeight: expiryBlockHeight
                )

                let envelope = try Self(
                    contract: contract,
                    claimPrivateKey: claimPrivateKey,
                    fundingTransactionHash: .init(naturalOrder: fundingTransactionHashData),
                    fundingOutputIndex: fundingOutputIndex,
                    fundingValue: fundingValue
                )
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.claimableEnvelopeDecodeSucceeded,
                    category: OpalBase.Diagnostics.Categories.claimable,
                    fields: fields + [OpalBaseDiagnostics.networkField(network)]
                )
                return envelope
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.claimableEnvelopeDecodeFailed,
                    category: OpalBase.Diagnostics.Categories.claimable,
                    fields: fields + OpalBaseDiagnostics.errorFields(
                        for: error,
                        fallback: OpalBase.Diagnostics.ErrorCodes.claimableInvalidEnvelope
                    )
                )
                throw error
            }
        }
    }

    public static func decode(
        from data: Data,
        on network: OpalBase.Network.Environment
    ) throws -> Self {
        let envelope = try decode(from: data)
        guard envelope.contract.network == network else {
            throw OpalBase.Claimable.Error.networkMismatch(
                expected: network,
                actual: envelope.contract.network
            )
        }
        return envelope
    }
}

private func makeClaimableNetworkTag(for network: OpalBase.Network.Environment) -> UInt8 {
    switch network {
    case .mainnet:
        return 0
    case .chipnet:
        return 1
    case .testnet:
        return 2
    }
}

private func makeClaimableNetwork(from networkTag: UInt8) throws -> OpalBase.Network.Environment {
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
