// OpalBase+Account+MosaicTransactionBroadcastCoordinator+Approval.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account.MosaicTransactionBroadcastCoordinator {
    struct ApprovalRequest: Sendable, Equatable {
        let reservationRequest: OpalFusion.Host.MosaicReservationRequest
        let reservationReference: OpalFusion.Host.MosaicReservationReference
        let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        let profile: OpalFusion.Mosaic.Profile
        let network: OpalBase.Network.Environment
        let totalInputSatoshis: UInt64?
        let totalOutputSatoshis: UInt64?
        let feeSatoshis: UInt64?

        init(
            reservationRequest: OpalFusion.Host.MosaicReservationRequest,
            reservationReference: OpalFusion.Host.MosaicReservationReference,
            completeTransaction: OpalFusion.Host.MosaicCompleteTransaction,
            profile: OpalFusion.Mosaic.Profile,
            network: OpalBase.Network.Environment,
            totalInputSatoshis: UInt64? = nil,
            totalOutputSatoshis: UInt64? = nil,
            feeSatoshis: UInt64? = nil
        ) {
            self.reservationRequest = reservationRequest
            self.reservationReference = reservationReference
            self.completeTransaction = completeTransaction
            self.profile = profile
            self.network = network
            self.totalInputSatoshis = totalInputSatoshis
            self.totalOutputSatoshis = totalOutputSatoshis
            self.feeSatoshis = feeSatoshis
        }
    }

    enum ApprovalDecision: Sendable, Equatable {
        case approved
        case rejected
    }

    typealias RequestApproval = @Sendable (
        ApprovalRequest
    ) async throws -> ApprovalDecision
}
#endif
