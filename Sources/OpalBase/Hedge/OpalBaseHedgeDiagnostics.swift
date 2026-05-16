// OpalBaseHedgeDiagnostics.swift

@preconcurrency import OpalHedge

enum OpalBaseHedgeDiagnostics {
    static func withCurrentTraceID<Success>(
        operation: () throws -> Success
    ) rethrows -> Success {
        try OpalBase.Diagnostics.withTraceID {
            let traceID = OpalBase.Diagnostics.currentTraceID ?? OpalBase.Diagnostics.TraceID()
            return try withTraceID(traceID, operation: operation)
        }
    }

    static nonisolated(nonsending) func withCurrentTraceID<Success>(
        operation: () async throws -> Success
    ) async throws -> Success {
        try await OpalBase.Diagnostics.withTraceID {
            let traceID = OpalBase.Diagnostics.currentTraceID ?? OpalBase.Diagnostics.TraceID()
            return try await withTraceID(traceID, operation: operation)
        }
    }

    static func withTraceID<Success>(
        _ traceID: OpalBase.Diagnostics.TraceID,
        operation: () throws -> Success
    ) rethrows -> Success {
        try OpalHedge.Diagnostics.withTraceID(traceID, operation: operation)
    }

    static nonisolated(nonsending) func withTraceID<Success>(
        _ traceID: OpalBase.Diagnostics.TraceID,
        operation: () async -> Success
    ) async -> Success {
        nonisolated(unsafe) let scopedOperation = operation
        return await OpalHedge.Diagnostics.withTraceID(traceID) {
            await scopedOperation()
        }
    }

    static nonisolated(nonsending) func withTraceID<Success>(
        _ traceID: OpalBase.Diagnostics.TraceID,
        operation: () async throws -> Success
    ) async throws -> Success {
        nonisolated(unsafe) let scopedOperation = operation
        return try await OpalHedge.Diagnostics.withTraceID(traceID) {
            try await scopedOperation()
        }
    }
}
