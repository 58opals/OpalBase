// OpalBase+Account+CashFusionParticipantReservationSource.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
        let reservation: CashFusionReservation

        func reserveParticipant(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            try await Self.loadParticipantReservation {
                try await reservation.reserveParticipant(for: roundIdentifier)
            }
        }

        func reserveParticipant(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            try await Self.loadParticipantReservation {
                try await reservation.reserveParticipant(for: context)
            }
        }
    }
}

extension _OpalBase.Account.CashFusionParticipantReservationSource {
    private static let noEligibleInputsSummary = "No eligible CashFusion inputs are available."
    private static let walletUnavailableSummary = "CashFusion wallet signing context is unavailable."
    private static let reservationUnavailableSummary = "CashFusion participant reservation is unavailable."
    private static let reservationCancelledSummary = "CashFusion participant reservation was cancelled."
    private static let unsupportedInputSummary = "CashFusion input selection is unsupported."
    private static let insufficientFundsSummary = "CashFusion input selection has insufficient value."
    private static let policyRejectedSummary = "CashFusion participant reservation does not satisfy round policy."

    static func participantReservationFailure(
        for error: Swift.Error
    ) -> OpalFusion.Host.ParticipantReservationFailure {
        if let failure = error as? OpalFusion.Host.ParticipantReservationFailure {
            return failure
        }

        if error is CancellationError {
            return reservationUnavailable(
                reason: .userCancelled,
                summary: reservationCancelledSummary
            )
        }

        if let accountError = error as? _OpalBase.Account.Error {
            return participantReservationFailure(for: accountError)
        }

        if let roundReservationError = error as? _OpalBase.Account.CashFusionRoundReservationError {
            return participantReservationFailure(for: roundReservationError)
        }

        if let addressBookError = error as? _OpalBase.Address.Book.Error {
            return participantReservationFailure(for: addressBookError)
        }

        return unknownReservationFailure()
    }

    private static func loadParticipantReservation(
        _ load: () async throws -> OpalFusion.Host.ParticipantReservation
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        do {
            return try validate(try await load())
        } catch {
            throw participantReservationFailure(for: error)
        }
    }

    private static func validate(
        _ participantReservation: OpalFusion.Host.ParticipantReservation
    ) throws -> OpalFusion.Host.ParticipantReservation {
        guard participantReservation.inputs.isEmpty == false else {
            throw hostPolicyRejected(
                reason: .noEligibleInputs,
                summary: noEligibleInputsSummary
            )
        }

        return participantReservation
    }

    private static func participantReservationFailure(
        for error: _OpalBase.Account.Error
    ) -> OpalFusion.Host.ParticipantReservationFailure {
        switch error {
        case .cashFusionHasNoSelectedInputs:
            return noEligibleInputsFailure()
        case .cashFusionUnsupportedSelectedInputs, .cashFusionCannotSpendTokenUTXOs:
            return hostPolicyRejected(
                reason: .unsupportedInput,
                summary: unsupportedInputSummary
            )
        case .cashFusionOutputAmountBelowMinimum:
            return hostPolicyRejected(
                reason: .insufficientFunds,
                summary: insufficientFundsSummary
            )
        case .cashFusionHasNoOutputAmounts:
            return hostPolicyRejected(
                reason: .policyRejected,
                summary: policyRejectedSummary
            )
        case .cashFusionReservationFailed(let underlyingError),
                .cashFusionOutputReservationFailed(let underlyingError):
            return participantReservationFailure(for: underlyingError)
        default:
            return unknownReservationFailure()
        }
    }

    private static func participantReservationFailure(
        for error: _OpalBase.Account.CashFusionRoundReservationError
    ) -> OpalFusion.Host.ParticipantReservationFailure {
        switch error {
        case .insufficientSelectedInputValue, .outputAmountBelowMinimum:
            return hostPolicyRejected(
                reason: .insufficientFunds,
                summary: insufficientFundsSummary
            )
        case .componentCountLimitExceeded, .invalidExcessFeeRange, .amountOverflow:
            return hostPolicyRejected(
                reason: .policyRejected,
                summary: policyRejectedSummary
            )
        case .dynamicReservationRequiresContext, .missingRoundReservation, .localOutputMismatch:
            return unknownReservationFailure()
        }
    }

    private static func participantReservationFailure(
        for error: _OpalBase.Address.Book.Error
    ) -> OpalFusion.Host.ParticipantReservationFailure {
        switch error {
        case .privateKeyNotFound, .utxoAlreadyReserved:
            return reservationUnavailable(
                reason: .walletLocked,
                summary: walletUnavailableSummary
            )
        case .utxoDuplicated:
            return hostPolicyRejected(
                reason: .unsupportedInput,
                summary: unsupportedInputSummary
            )
        case .utxoNotFound:
            return noEligibleInputsFailure()
        case .insufficientFunds:
            return hostPolicyRejected(
                reason: .insufficientFunds,
                summary: insufficientFundsSummary
            )
        default:
            return unknownReservationFailure()
        }
    }

    private static func noEligibleInputsFailure() -> OpalFusion.Host.ParticipantReservationFailure {
        hostPolicyRejected(
            reason: .noEligibleInputs,
            summary: noEligibleInputsSummary
        )
    }

    private static func unknownReservationFailure() -> OpalFusion.Host.ParticipantReservationFailure {
        reservationUnavailable(
            reason: .unknown,
            summary: reservationUnavailableSummary
        )
    }

    private static func hostPolicyRejected(
        reason: OpalFusion.Host.ParticipantReservationFailure.Reason,
        summary: String
    ) -> OpalFusion.Host.ParticipantReservationFailure {
        .hostPolicyRejected(
            reason: reason,
            summary: summary
        )
    }

    private static func reservationUnavailable(
        reason: OpalFusion.Host.ParticipantReservationFailure.Reason,
        summary: String
    ) -> OpalFusion.Host.ParticipantReservationFailure {
        .reservationUnavailable(
            reason: reason,
            summary: summary
        )
    }
}
#endif
