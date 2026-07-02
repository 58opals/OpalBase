// ProtectedMaterialResetProbe.swift

import Foundation

final class ProtectedMaterialResetProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var resetWasRecorded = false

    var wasReset: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resetWasRecorded
    }

    func recordReset() {
        lock.lock()
        resetWasRecorded = true
        lock.unlock()
    }
}
