// Network+FulcrumServerVersion.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumServerVersion: Sendable, Equatable {
        public let serverVersion: String
        public let negotiatedProtocolVersion: ProtocolVersion
        
        public init(serverVersion: String, negotiatedProtocolVersion: ProtocolVersion) {
            self.serverVersion = serverVersion
            self.negotiatedProtocolVersion = negotiatedProtocolVersion
        }
    }
}
