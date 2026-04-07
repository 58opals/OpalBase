#if os(macOS)
// OpalBase+Account+CashFusionSelectedInputClassification.swift

import Foundation

extension _OpalBase.Account {
    struct CashFusionSelectedInputClassification: Sendable {
        enum Status: Sendable {
            case eligible(CashFusionReservation.ReservedInput)
            case blocked(OpalBase.Account.CashFusionBlockedReason)
        }

        let unspentOutput: OpalBase.Transaction.Output.Unspent
        let status: Status
    }
}

extension _OpalBase.Account.CashFusionSelectedInputClassification {
    var isEligible: Bool {
        guard case .eligible = status else {
            return false
        }

        return true
    }

    var publicEligibility: OpalBase.Account.CashFusionUTXOEligibility {
        switch status {
        case .eligible:
            return .init(
                unspentOutput: unspentOutput,
                status: .eligible
            )
        case .blocked(let reason):
            return .init(
                unspentOutput: unspentOutput,
                status: .blocked(reason)
            )
        }
    }
}
#endif
