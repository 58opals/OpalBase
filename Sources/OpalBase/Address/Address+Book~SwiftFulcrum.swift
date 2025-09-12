// Address+Book~SwiftFulcrum.swift

import Foundation

extension Address.Book {
    func enqueueRequest(_ request: @escaping @Sendable () async throws -> Void) {
        requestQueue.append(request)
    }
    
    func processQueuedRequests() async {
        guard !requestQueue.isEmpty else { return }
        
        let currentRequests = requestQueue
        requestQueue.removeAll()
        for request in currentRequests {
            do { try await request() }
            catch { requestQueue.append(request) }
        }
    }
    
    func executeOrEnqueue(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        do { try await operation() }
        catch {
            enqueueRequest(operation)
            throw error
        }
    }
    
    func executeOrEnqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch {
            enqueueRequest { _ = try await operation() }
            throw error
        }
    }
}
