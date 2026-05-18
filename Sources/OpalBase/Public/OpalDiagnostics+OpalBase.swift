// OpalDiagnostics+OpalBase.swift

import Foundation
@preconcurrency public import OpalDiagnostics

public extension OpalDiagnostics {
    static func record(
        _ event: Event,
        category: Category,
        level: Level? = nil,
        traceID: TraceID? = nil,
        fields: [Field] = []
    ) {
        logger(category: category).record(
            event: event,
            level: level ?? defaultLevel(for: event),
            traceID: traceID,
            fields: fields
        )
    }

    static func recentRecords(
        category: Category? = nil,
        level: Level? = nil,
        traceID: TraceID? = nil,
        event: Event? = nil,
        from startDate: Date? = nil,
        through endDate: Date? = nil
    ) -> [Record] {
        recentRecords(
            matching: .init(
                category: category,
                level: level,
                traceID: traceID,
                event: event,
                from: startDate,
                through: endDate
            )
        )
    }

    static func withTraceID<Success>(
        _ traceID: TraceID,
        operation: () throws -> Success
    ) rethrows -> Success {
        try withTraceID(Optional(traceID), operation: operation)
    }

    static nonisolated(nonsending) func withTraceID<Success>(
        _ traceID: TraceID,
        operation: () async -> Success
    ) async -> Success {
        nonisolated(unsafe) let scopedOperation = operation
        return await withTraceID(Optional(traceID)) {
            await scopedOperation()
        }
    }

    static nonisolated(nonsending) func withTraceID<Success>(
        _ traceID: TraceID,
        operation: () async throws -> Success
    ) async throws -> Success {
        nonisolated(unsafe) let scopedOperation = operation
        return try await withTraceID(Optional(traceID)) {
            try await scopedOperation()
        }
    }

    static func withTraceID<Success>(
        operation: () throws -> Success
    ) rethrows -> Success {
        try withTraceID(resolveTraceID(), operation: operation)
    }

    static nonisolated(nonsending) func withTraceID<Success>(
        operation: () async -> Success
    ) async -> Success {
        let traceID = resolveTraceID()
        nonisolated(unsafe) let scopedOperation = operation
        return await withTraceID(traceID) {
            await scopedOperation()
        }
    }

    static nonisolated(nonsending) func withTraceID<Success>(
        operation: () async throws -> Success
    ) async throws -> Success {
        let traceID = resolveTraceID()
        nonisolated(unsafe) let scopedOperation = operation
        return try await withTraceID(traceID) {
            try await scopedOperation()
        }
    }

    static func withNewTraceID<Success>(
        operation: (TraceID) throws -> Success
    ) rethrows -> Success {
        let traceID = TraceID()
        return try withTraceID(traceID) {
            try operation(traceID)
        }
    }

    static nonisolated(nonsending) func withNewTraceID<Success>(
        operation: (TraceID) async -> Success
    ) async -> Success {
        let traceID = TraceID()
        nonisolated(unsafe) let scopedOperation = operation
        return await withTraceID(traceID) {
            await scopedOperation(traceID)
        }
    }

    static nonisolated(nonsending) func withNewTraceID<Success>(
        operation: (TraceID) async throws -> Success
    ) async throws -> Success {
        let traceID = TraceID()
        nonisolated(unsafe) let scopedOperation = operation
        return try await withTraceID(traceID) {
            try await scopedOperation(traceID)
        }
    }
}

private extension OpalDiagnostics {
    static func resolveTraceID() -> TraceID {
        currentTraceID ?? TraceID()
    }

    static func defaultLevel(for event: Event) -> Level {
        if event.rawValue.hasSuffix(".failed") {
            return .error
        }
        if event.rawValue.hasSuffix(".started") || event.rawValue.hasSuffix(".succeeded") {
            return .debug
        }
        return .notice
    }
}
