// OpalBase+Account+MosaicTransactionPresence.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    /// Exact transaction presence; uncertainty is data and never authorizes dispatch.
    enum MosaicTransactionPresence: Sendable, Equatable {
        case present(Observation)
        case authoritativeAbsence
        case unknown(UnknownReason)
    }
}
#endif
