// RawTransactionSequence.swift

import Foundation

final class RawTransactionSequence: @unchecked Sendable {
    enum Error: Swift.Error {
        case exhausted
    }

    private let lock = NSLock()
    private var values: [Data]

    init(_ values: [Data]) {
        self.values = values
    }

    func next() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { throw Error.exhausted }
        return values.removeFirst()
    }
}
