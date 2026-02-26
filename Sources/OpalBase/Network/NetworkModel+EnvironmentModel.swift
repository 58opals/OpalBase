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
