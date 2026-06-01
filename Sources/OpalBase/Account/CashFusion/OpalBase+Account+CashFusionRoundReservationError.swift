// OpalBase+Account+CashFusionRoundReservationError.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    enum CashFusionRoundReservationError: Swift.Error, Equatable {
        case dynamicReservationRequiresContext(OpalFusion.Round.Identifier)
        case missingRoundReservation(OpalFusion.Round.Identifier)
        case invalidExcessFeeRange(minimum: UInt64, maximum: UInt64)
        case componentCountLimitExceeded(required: Int, limit: UInt32)
        case insufficientSelectedInputValue(required: UInt64, available: UInt64)
        case outputAmountBelowMinimum(minimum: UInt64, actual: UInt64)
        case localOutputMismatch
        case amountOverflow
    }
}
#endif
