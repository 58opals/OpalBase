// OpalBase+Account+MosaicPrivateAlphaRuntime+SigningApproval.swift

#if os(macOS)
import Foundation
import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact unsigned proposal presented only after wallet and profile validation.
    /// This participant-identifying data belongs in private review, never diagnostics.
    /// This is not a signed transaction or permission to broadcast.
    @_spi(MosaicPrivateAlpha)
    public struct SigningApprovalRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha)
        public struct Input: Sendable, Equatable {
            @_spi(MosaicPrivateAlpha) public let transactionHash: OpalBase.Transaction.Hash
            @_spi(MosaicPrivateAlpha) public let outputIndex: UInt32
            @_spi(MosaicPrivateAlpha) public let valueSatoshis: UInt64
            @_spi(MosaicPrivateAlpha) public let lockingScript: Data
        }

        @_spi(MosaicPrivateAlpha)
        public struct Output: Sendable, Equatable {
            @_spi(MosaicPrivateAlpha) public let valueSatoshis: UInt64
            @_spi(MosaicPrivateAlpha) public let lockingScript: Data
            @_spi(MosaicPrivateAlpha) public let serializedBytes: Data
        }

        @_spi(MosaicPrivateAlpha) public let unsignedTransactionBytes: Data
        @_spi(MosaicPrivateAlpha) public let roundIdentifier: Data
        @_spi(MosaicPrivateAlpha) public let transcriptRoot: Data
        @_spi(MosaicPrivateAlpha) public let walletReservationIdentifier: UUID
        @_spi(MosaicPrivateAlpha) public let walletGeneration: UInt64
        @_spi(MosaicPrivateAlpha) public let reservationExpiresAt: Date
        @_spi(MosaicPrivateAlpha) public let expectedNetworkGenesisHash: Data
        @_spi(MosaicPrivateAlpha) public let profile: Profile
        @_spi(MosaicPrivateAlpha) public let spentInputs: [Input]
        @_spi(MosaicPrivateAlpha) public let localInputIndices: [Int]
        @_spi(MosaicPrivateAlpha) public let expectedLocalOutputs: [Output]
        @_spi(MosaicPrivateAlpha) public let outputs: [Output]
        @_spi(MosaicPrivateAlpha) public let feeSatoshis: UInt64

        init(
            validated request: OpalFusion.Host.MosaicTransactionSigningRequest,
            transaction: OpalBase.Transaction,
            lease: OpalFusion.Host.MosaicReservationLease,
            profile: OpalFusion.Mosaic.Profile,
            networkGenesisHash: [UInt8],
            feeSatoshis: UInt64
        ) throws {
            unsignedTransactionBytes = Data(request.unsignedTransactionBytes)
            roundIdentifier = Data(request.roundIdentifier)
            transcriptRoot = Data(request.transcriptRoot)
            walletReservationIdentifier = request.reservationReference.identifier
            walletGeneration = request.reservationReference.generation
            reservationExpiresAt = lease.expiresAt
            expectedNetworkGenesisHash = Data(networkGenesisHash)
            self.profile = .init(profile)
            spentInputs = request.spentInputs.map {
                .init(transactionHash: .init(reverseOrder: Data($0.outpointTransactionHashBytes)),
                      outputIndex: $0.outpointIndex, valueSatoshis: $0.amountSatoshis,
                      lockingScript: Data($0.lockingScriptBytes))
            }
            localInputIndices = request.localInputIndices
            let outputs = try transaction.outputs.map {
                Output(valueSatoshis: $0.value, lockingScript: $0.lockingScript,
                       serializedBytes: try $0.encode())
            }
            self.outputs = outputs
            expectedLocalOutputs = try request.expectedLocalOutputs.map { expected in
                guard let output = outputs.first(where: {
                    $0.valueSatoshis == expected.amountSatoshis
                        && $0.lockingScript == Data(expected.lockingScriptBytes)
                }) else { throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal }
                return output
            }
            self.feeSatoshis = feeSatoshis
        }
    }

    /// Optional application approval before durable signing intent. Throwing denies signing.
    /// The caller owns presentation and durable approval binding; no timeout is extended.
    @_spi(MosaicPrivateAlpha)
    public struct SigningApproval: Sendable {
        let approve: @Sendable (SigningApprovalRequest) async throws -> Void

        @_spi(MosaicPrivateAlpha)
        public init(approve: @escaping @Sendable (SigningApprovalRequest) async throws -> Void) {
            self.approve = approve
        }
    }
}
#endif
