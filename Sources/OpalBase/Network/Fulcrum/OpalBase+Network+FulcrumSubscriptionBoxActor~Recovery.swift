// OpalBase.Network+FulcrumSubscriptionBoxActor~Recovery.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.FulcrumSubscriptionBoxActor {
    func evaluateTerminationDeferralForRecovery() async -> Bool {
        await Task.yield()

        if isTerminated {
            return true
        }

        if isExpectingResubscribe {
            return true
        }

        return false
    }

    func checkTerminationErrorSuppression(_ error: Swift.Error) -> Bool {
        guard isTerminated else { return false }
        return checkClientCancellation(error)
    }

    func checkRecoverability(_ error: Swift.Error) -> Bool {
        guard let fulcrumError = error as? SwiftFulcrum.Client.Error else { return false }
        switch fulcrumError {
        case .transport(.connectionClosed),
                .transport(.reconnectFailed),
                .transport(.heartbeatTimeout),
                .client(.cancelled):
            return true
        default:
            return false
        }
    }

    func checkClientCancellation(_ error: Swift.Error) -> Bool {
        guard let fulcrumError = error as? SwiftFulcrum.Client.Error else { return false }
        if case .client(.cancelled) = fulcrumError {
            return true
        }
        return false
    }
}

