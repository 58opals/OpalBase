#if os(macOS)
// OpalBase+Account+CashFusionPilotAvailability.swift

import Foundation

extension _OpalBase.Account {
    public enum CashFusionPilotAvailability: Sendable, Equatable {
        case available
        case unavailable
    }
}
#endif
