// Network+Configuration~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension Network.Configuration {
    var fulcrumBootstrapServers: [URL] {
        let overrides = Network.ServerCatalog.makeNormalizedServers(serverURLs)
        if !overrides.isEmpty { return overrides }
        return serverCatalog.servers(for: network)
    }
    
    func makeFulcrumServerCatalogLoader() -> FulcrumServerCatalogLoader {
        let overrides = Network.ServerCatalog.makeNormalizedServers(serverURLs)
        let defaults = serverCatalog.servers(for: network)
        let expectedFulcrumNetwork = network.fulcrumNetwork
        
        return FulcrumServerCatalogLoader { fulcrumNetwork, fallback in
            assert(fulcrumNetwork == expectedFulcrumNetwork, "Fulcrum network mismatch for configuration environment: \(network)")
            let merged = Network.ServerCatalog.makeMergedServers(
                primary: overrides,
                secondary: defaults,
                fallback: fallback
            )
            guard !merged.isEmpty else { throw Fulcrum.Error.transport(.setupFailed) }
            return merged
        }
    }
}
