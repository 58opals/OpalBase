// OpalBase+Account+CashFusionPilotAvailability.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    public enum CashFusionPilotAvailability: Sendable, Equatable {
        case available
        case unavailable
    }
}
#endif
