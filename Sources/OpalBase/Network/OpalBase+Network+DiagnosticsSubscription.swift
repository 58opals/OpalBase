// OpalBase+Network+DiagnosticsSubscription.swift

import Foundation

extension _OpalBase.Network {
    public struct DiagnosticsSubscription: Sendable, Equatable {
        public let methodPath: String
        public let identifier: String?
        
        public init(methodPath: String, identifier: String?) {
            self.methodPath = methodPath
            self.identifier = identifier
        }
    }
}
