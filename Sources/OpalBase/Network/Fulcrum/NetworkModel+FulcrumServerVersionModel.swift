// NetworkModel+FulcrumServerVersionModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumServerVersionModel: Sendable, Equatable {
        public let serverVersion: String
        public let negotiatedProtocolVersion: NetworkModel.ProtocolVersion
        
        public init(serverVersion: String, negotiatedProtocolVersion: NetworkModel.ProtocolVersion) {
            self.serverVersion = serverVersion
            self.negotiatedProtocolVersion = negotiatedProtocolVersion
        }
    }
}
