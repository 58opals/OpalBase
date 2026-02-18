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
    var fulcrumNetwork: SwiftFulcrum.FulcrumClient.Configuration.NetworkModel {
        switch self {
        case .mainnet:
            return .mainnet
        case .chipnet, .testnet:
            return .testnet
        }
    }
    
    init(_ fulcrumNetwork: SwiftFulcrum.FulcrumClient.Configuration.NetworkModel) {
        switch fulcrumNetwork {
        case .mainnet: self = .mainnet
        case .testnet: self = .testnet
        }
    }
}
