// NetworkModel+EnvironmentModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public enum EnvironmentModel: Sendable, Equatable {
        case mainnet
        case chipnet
        case testnet
    }
}

extension NetworkModel.EnvironmentModel {
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
