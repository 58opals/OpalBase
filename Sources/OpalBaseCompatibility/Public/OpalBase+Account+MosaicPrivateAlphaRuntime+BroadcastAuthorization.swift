import OpalBaseCore
import Foundation

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Immutable application authority for one exact transaction and chain client.
    /// Retaining or replaying this value never renews its original approval interval.
    @_spi(MosaicPrivateAlpha)
    public struct BroadcastAuthorization: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let request: BroadcastApprovalRequest
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let attestation: ChainAttestation
        @_spi(MosaicPrivateAlpha) public let operatorConfirmedAt: Date
        @_spi(MosaicPrivateAlpha) public let expiresAt: Date

        @_spi(MosaicPrivateAlpha)
        public init?(
            request: BroadcastApprovalRequest,
            binding: Binding,
            attestation: ChainAttestation,
            operatorConfirmedAt: Date,
            expiresAt: Date
        ) {
            guard operatorConfirmedAt.timeIntervalSinceReferenceDate.isFinite,
                  expiresAt.timeIntervalSinceReferenceDate.isFinite,
                  request.reservationExpiresAt.timeIntervalSinceReferenceDate.isFinite,
                  operatorConfirmedAt < expiresAt,
                  expiresAt <= request.reservationExpiresAt,
                  request.network == attestation.network,
                  request.expectedNetworkGenesisHash == attestation.genesisHash,
                  request.expectedNetworkGenesisHash == Data(request.network.mosaicGenesisHash),
                  attestation.serverURLs.isEmpty == false else { return nil }
            self.request = request
            self.binding = binding
            self.attestation = attestation
            self.operatorConfirmedAt = operatorConfirmedAt
            self.expiresAt = expiresAt
        }

        func authorizes(
            _ currentRequest: BroadcastApprovalRequest,
            binding currentBinding: Binding,
            attestation currentAttestation: ChainAttestation,
            at currentDate: Date
        ) -> Bool {
            request == currentRequest
                && binding == currentBinding
                && attestation == currentAttestation
                && currentDate.timeIntervalSinceReferenceDate.isFinite
                && operatorConfirmedAt <= currentDate
                && currentDate < expiresAt
        }
    }
}
#endif
