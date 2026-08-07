// OpalBase+Account+MosaicAttemptJournal.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Durable write-ahead records for one non-resumable Mosaic attempt.
    ///
    /// Records contain wallet-private material. A backend must append each record atomically and durably
    /// before returning. Serialization, encryption at rest, and storage location remain app-owned.
    struct MosaicAttemptJournal: Sendable {
        private let recordAppender: @Sendable (Record) async throws -> Void

        init(
            appendRecord: @escaping @Sendable (Record) async throws -> Void
        ) {
            recordAppender = appendRecord
        }

        func append(_ record: Record) async throws {
            try await recordAppender(record)
        }
    }
}
#endif
