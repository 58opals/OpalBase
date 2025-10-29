// Network+FulcrumSession+Subscription.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public struct Subscription<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: Sendable {
        private let fetchLatestInitialResponseHandler: @Sendable () async -> Initial
        private let checkIsActiveHandler: @Sendable () async -> Bool
        private let cancelHandler: @Sendable () async -> Void
        private let resubscribeHandler: @Sendable () async throws -> Initial
        
        public let identifier: UUID
        public let updates: AsyncThrowingStream<Notification, Swift.Error>
        
        init(identifier: UUID,
             updates: AsyncThrowingStream<Notification, Swift.Error>,
             fetchLatestInitialResponse: @escaping @Sendable () async -> Initial,
             checkIsActive: @escaping @Sendable () async -> Bool,
             cancel: @escaping @Sendable () async -> Void,
             resubscribe: @escaping @Sendable () async throws -> Initial) {
            self.identifier = identifier
            self.updates = updates
            self.fetchLatestInitialResponseHandler = fetchLatestInitialResponse
            self.checkIsActiveHandler = checkIsActive
            self.cancelHandler = cancel
            self.resubscribeHandler = resubscribe
        }
        
        public func fetchLatestInitialResponse() async -> Initial {
            await fetchLatestInitialResponseHandler()
        }
        
        public func checkIsActive() async -> Bool {
            await checkIsActiveHandler()
        }
        
        public func cancel() async {
            await cancelHandler()
        }
        
        public func resubscribe() async throws -> Initial {
            try await resubscribeHandler()
        }
    }
}
