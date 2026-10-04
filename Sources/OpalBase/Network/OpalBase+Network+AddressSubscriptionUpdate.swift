// OpalBase+Network+AddressSubscriptionUpdate.swift

import Foundation

extension _OpalBase.Network {
    public struct AddressSubscriptionUpdate: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case initialSnapshot
            case change
        }
        
        public let kind: Kind
        public let address: String
        public let status: String?
        /// Present for producer-observed subscriptions; retained across asynchronous adapter hops.
        public let connectionGeneration: UInt64?
        
        public init(kind: Kind, address: String, status: String?, connectionGeneration: UInt64? = nil) {
            self.kind = kind
            self.address = address
            self.status = status
            self.connectionGeneration = connectionGeneration
        }
    }
}
