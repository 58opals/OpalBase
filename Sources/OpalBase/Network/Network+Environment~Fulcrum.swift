// Network+Environment.swift

import Foundation
import SwiftFulcrum

extension Network {
    public enum Environment: Sendable, Equatable {
        case mainnet
        case chipnet
        case testnet
    }
}

extension Network.Environment {
    var fulcrumNetwork: Fulcrum.Configuration.Network {
        switch self {
        case .mainnet:
            return .mainnet
        case .chipnet, .testnet:
            return .testnet
        }
    }
    
    init(_ fulcrumNetwork: Fulcrum.Configuration.Network) {
        switch fulcrumNetwork {
        case .mainnet: self = .mainnet
        case .testnet: self = .testnet
        }
    }
}
