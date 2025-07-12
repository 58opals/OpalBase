// Address+Book~SwiftFulcrum.swift

import Foundation

extension Address.Book {
    func enqueueRequest(_ request: @escaping () async throws -> Void) {
        requestQueue.append(request)
    }
    
    func processQueuedRequests() async {
        while !requestQueue.isEmpty {
            let request = requestQueue.removeFirst()
            do { try await request() } catch { /* handle/log error if needed */ }
        }
    }
}
