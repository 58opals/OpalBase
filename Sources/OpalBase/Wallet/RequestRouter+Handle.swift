// RequestRouter+Handle.swift

import Foundation

extension RequestRouter {
    public struct Handle: Sendable {
        let router: RequestRouter
        public let key: Key
        
        init(router: RequestRouter, key: Key) {
            self.router = router
            self.key = key
        }
    }
}

extension RequestRouter.Handle {
    public func enqueue(priority: TaskPriority? = nil,
                        retryPolicy: RequestRouter.RetryPolicy = .retry,
                        operation: @escaping @Sendable () async throws -> Void) async -> RequestRouter.Key {
        await router.enqueue(key: key,
                             priority: priority,
                             retryPolicy: retryPolicy,
                             operation: operation)
        return key
    }
    
    public func perform<Value: Sendable>(priority: TaskPriority? = nil,
                                         operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await router.perform(key: key,
                                 priority: priority,
                                 operation: operation)
    }
    
    public func cancel() async {
        await router.cancel(key: key)
    }
}
