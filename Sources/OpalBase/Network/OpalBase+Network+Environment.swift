// OpalBase+Network+Environment.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    public enum Environment: Sendable, Equatable {
        case mainnet
        case chipnet
        case testnet
    }
}

extension _OpalBase.Network.Environment {
    var fulcrumNetwork: SwiftFulcrum.Client.Configuration.Network {
        switch self {
        case .mainnet:
            return .mainnet
        case .chipnet, .testnet:
            return .testnet
        }
    }
    
    init(_ fulcrumNetwork: SwiftFulcrum.Client.Configuration.Network) {
        switch fulcrumNetwork {
        case .mainnet: self = .mainnet
        case .testnet: self = .testnet
        }
    }
}
