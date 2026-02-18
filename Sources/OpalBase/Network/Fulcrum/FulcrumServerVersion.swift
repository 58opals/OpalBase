// Network+FulcrumServerVersion.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumServerVersion: Sendable, Equatable {
        public let serverVersion: String
        public let negotiatedProtocolVersion: ProtocolVersionModel
        
        public init(serverVersion: String, negotiatedProtocolVersion: ProtocolVersionModel) {
            self.serverVersion = serverVersion
            self.negotiatedProtocolVersion = negotiatedProtocolVersion
        }
    }
}
