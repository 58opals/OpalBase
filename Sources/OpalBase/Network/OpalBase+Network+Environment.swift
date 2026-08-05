// OpalBase+Network+Environment.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    public enum Environment: String, Codable, Sendable, Equatable, Hashable {
        case mainnet
        case testnet
        case chipnet
    }
}

extension _OpalBase.Network.Environment {
    var fulcrumNetwork: SwiftFulcrum.Client.Configuration.Network {
        switch self {
        case .mainnet:
            return .mainnet
        case .chipnet:
            return .chipnet
        case .testnet:
            return .testnet
        }
    }
    
    init(_ fulcrumNetwork: SwiftFulcrum.Client.Configuration.Network) {
        switch fulcrumNetwork {
        case .mainnet: self = .mainnet
        case .chipnet: self = .chipnet
        case .testnet: self = .testnet
        }
    }
}
