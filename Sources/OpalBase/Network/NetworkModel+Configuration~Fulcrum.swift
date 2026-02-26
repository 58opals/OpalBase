// NetworkModel+Configuration~FulcrumClient.swift

import Foundation
import SwiftFulcrum

extension NetworkModel.Configuration {
    var fulcrumBootstrapServers: [URL] {
        let overrides = NetworkModel.ServerCatalogModel.makeNormalizedServers(serverURLs)
        if !overrides.isEmpty { return overrides }
        return serverCatalog.listServers(for: network)
    }
    
    func makeFulcrumServerCatalogRepository() -> SwiftFulcrum.FulcrumServerCatalogRepository {
        let overrides = NetworkModel.ServerCatalogModel.makeNormalizedServers(serverURLs)
        let defaults = serverCatalog.listServers(for: network)
        let expectedFulcrumNetwork = network.fulcrumNetwork
        
        return SwiftFulcrum.FulcrumServerCatalogRepository { fulcrumNetwork, fallback in
            assert(fulcrumNetwork == expectedFulcrumNetwork, "FulcrumClient network mismatch for configuration environment: \(network)")
            let merged = NetworkModel.ServerCatalogModel.makeMergedServers(
                primary: overrides,
                secondary: defaults,
                fallback: fallback
            )
            guard !merged.isEmpty else { throw SwiftFulcrum.FulcrumClient.Error.transport(.setupFailed) }
            return merged
        }
    }
}
