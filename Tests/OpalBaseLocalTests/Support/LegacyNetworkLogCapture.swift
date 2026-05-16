// LegacyNetworkLogCapture.swift

import Foundation
@testable import OpalBase

final class LegacyNetworkLogCapture: @unchecked Sendable {
    struct Entry {
        let level: OpalBase.Network.LogLevel
        let message: String
        let metadata: [String: String]?
        let file: String
        let function: String
        let line: UInt
    }

    private let lock = NSLock()
    private var recordedEntries: [Entry] = []

    func append(
        level: OpalBase.Network.LogLevel,
        message: String,
        metadata: [String: String]?,
        file: String,
        function: String,
        line: UInt
    ) {
        lock.withLock {
            recordedEntries.append(
                .init(
                    level: level,
                    message: message,
                    metadata: metadata,
                    file: file,
                    function: function,
                    line: line
                )
            )
        }
    }

    func entries() -> [Entry] {
        lock.withLock { recordedEntries }
    }
}
