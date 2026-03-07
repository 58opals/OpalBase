// OpalBase.Network+FulcrumServerVersion.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    public struct FulcrumServerVersion: Sendable, Equatable {
        public let serverVersion: String
        public let negotiatedProtocolVersion: OpalBase.Network.ProtocolVersion
        
        public init(serverVersion: String, negotiatedProtocolVersion: OpalBase.Network.ProtocolVersion) {
            self.serverVersion = serverVersion
            self.negotiatedProtocolVersion = negotiatedProtocolVersion
        }
    }
}
