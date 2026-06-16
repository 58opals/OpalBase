// OpalBase+WalletObservabilityInteractor.swift

import Foundation
import OpalDiagnostics

public extension OpalBase {
    /// Observability lane for redacted OpalDiagnostics records only.
    struct WalletObservabilityInteractor: Sendable {
        public init() {}

        public func recentRecords(
            category: OpalDiagnostics.Category? = nil,
            level: OpalDiagnostics.Level? = nil,
            traceID: OpalDiagnostics.TraceID? = nil,
            event: OpalDiagnostics.Event? = nil,
            from startDate: Date? = nil,
            through endDate: Date? = nil
        ) -> [OpalDiagnostics.Record] {
            OpalDiagnostics.recentRecords(
                category: category,
                level: level,
                traceID: traceID,
                event: event,
                from: startDate,
                through: endDate
            )
        }
    }
}
