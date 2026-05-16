// TokenMetadataSyncRequestRecorder.swift

import Foundation

final class TokenMetadataSyncRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requestedURLs: [URL] = .init()

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs
    }

    func append(_ url: URL) {
        lock.lock()
        requestedURLs.append(url)
        lock.unlock()
    }
}
