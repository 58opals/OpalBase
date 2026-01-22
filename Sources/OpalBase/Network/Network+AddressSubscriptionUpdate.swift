// Network+AddressSubscriptionUpdate.swift

import Foundation

extension Network {
    public struct AddressSubscriptionUpdate: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case initialSnapshot
            case change
        }
        
        public let kind: Kind
        public let address: String
        public let status: String?
        
        public init(kind: Kind, address: String, status: String?) {
            self.kind = kind
            self.address = address
            self.status = status
        }
    }
}
