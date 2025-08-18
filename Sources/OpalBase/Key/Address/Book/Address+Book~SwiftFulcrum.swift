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
    
    func executeOrEnqueue(_ operation: @escaping () async throws -> Void) async throws {
        do { try await operation() }
        catch {
            enqueueRequest(operation)
            throw error
        }
    }
    
    func executeOrEnqueue<T: Sendable>(_ operation: @escaping () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch {
            enqueueRequest { _ = try await operation() }
            throw error
        }
    }
}
