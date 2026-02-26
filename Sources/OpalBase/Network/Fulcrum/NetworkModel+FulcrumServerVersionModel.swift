// NetworkModel+FulcrumServerVersionModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumServerVersionModel: Sendable, Equatable {
        public let serverVersion: String
        public let negotiatedProtocolVersion: ProtocolVersionModel
        
        public init(serverVersion: String, negotiatedProtocolVersion: ProtocolVersionModel) {
            self.serverVersion = serverVersion
            self.negotiatedProtocolVersion = negotiatedProtocolVersion
        }
    }
}
