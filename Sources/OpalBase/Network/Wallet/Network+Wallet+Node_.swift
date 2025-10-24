// Network+Wallet+Node_.swift

import Foundation

//extension Network.Wallet {
//    public protocol Node: Sendable {
//        func balance(for address: Address, includeUnconfirmed: Bool) async throws -> Satoshi
//        func unspentOutputs(for address: Address) async throws -> [Transaction.Output.Unspent]
//        func simpleHistory(for address: Address,
//                           fromHeight: UInt?,
//                           toHeight: UInt?,
//                           includeUnconfirmed: Bool) async throws -> [Transaction.Simple]
//        func detailedHistory(for address: Address,
//                             fromHeight: UInt?,
//                             toHeight: UInt?,
//                             includeUnconfirmed: Bool) async throws -> [Transaction.Detailed]
//        func subscribe(to address: Address) async throws -> SubscriptionStream
//    }
//}
//
//extension Network.Wallet {
//    public struct SubscriptionStream: Sendable {
//        public struct Notification: Sendable, Equatable {
//            public let status: String?
//            
//            public init(status: String?) {
//                self.status = status
//            }
//        }
//        
//        public let id: UUID
//        public let initialStatus: String
//        public let updates: AsyncThrowingStream<Notification, Swift.Error>
//        public let cancel: @Sendable () async -> Void
//        
//        public init(id: UUID,
//                    initialStatus: String,
//                    updates: AsyncThrowingStream<Notification, Swift.Error>,
//                    cancel: @escaping @Sendable () async -> Void) {
//            self.id = id
//            self.initialStatus = initialStatus
//            self.updates = updates
//            self.cancel = cancel
//        }
//    }
//}
//
//extension Network.Wallet {
//    public struct NodeError: Swift.Error, Sendable, Equatable {
//        public enum Reason: Sendable, Equatable {
//            case rejected(code: Int?, message: String)
//            case transport(description: String)
//            case coding(description: String)
//            case unknown(description: String)
//        }
//        
//        public let reason: Reason
//        
//        public init(reason: Reason) {
//            self.reason = reason
//        }
//    }
//}
