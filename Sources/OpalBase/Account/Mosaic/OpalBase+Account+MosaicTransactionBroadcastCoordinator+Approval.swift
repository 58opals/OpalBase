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
