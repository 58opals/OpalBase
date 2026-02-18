// Network+Configuration~FulcrumClient.swift

import Foundation
import SwiftFulcrum

extension Network.Configuration {
    var fulcrumBootstrapServers: [URL] {
        let overrides = Network.ServerCatalog.makeNormalizedServers(serverURLs)
        if !overrides.isEmpty { return overrides }
        return serverCatalog.listServers(for: network)
    }
    
    func makeFulcrumServerCatalogRepository() -> SwiftFulcrum.FulcrumServerCatalogRepository {
        let overrides = Network.ServerCatalog.makeNormalizedServers(serverURLs)
        let defaults = serverCatalog.listServers(for: network)
        let expectedFulcrumNetwork = network.fulcrumNetwork
        
        return SwiftFulcrum.FulcrumServerCatalogRepository { fulcrumNetwork, fallback in
            assert(fulcrumNetwork == expectedFulcrumNetwork, "FulcrumClient network mismatch for configuration environment: \(network)")
            let merged = Network.ServerCatalog.makeMergedServers(
                primary: overrides,
                secondary: defaults,
                fallback: fallback
            )
            guard !merged.isEmpty else { throw SwiftFulcrum.FulcrumClient.Error.transport(.setupFailed) }
            return merged
        }
    }
}
