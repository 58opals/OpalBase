// OpalBase+Network+Configuration~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Configuration {
    var fulcrumBootstrapServers: [URL] {
        let overrides = OpalBase.Network.ServerCatalogModel.makeNormalizedServers(serverURLs)
        if !overrides.isEmpty { return overrides }
        return serverCatalog.listServers(for: network)
    }
    
    func makeFulcrumServerCatalogRepository() -> SwiftFulcrum.ServerCatalog.Repository {
        let overrides = OpalBase.Network.ServerCatalogModel.makeNormalizedServers(serverURLs)
        let defaults = serverCatalog.listServers(for: network)
        let expectedFulcrumNetwork = network.fulcrumNetwork
        
        return SwiftFulcrum.ServerCatalog.Repository(load: { fulcrumNetwork, fallback in
            guard fulcrumNetwork == expectedFulcrumNetwork else {
                throw SwiftFulcrum.Client.Error.client(
                    .protocolMismatch(
                        "FulcrumClient network mismatch. configuredEnvironment=\(network), expectedFulcrumNetwork=\(expectedFulcrumNetwork), requestedFulcrumNetwork=\(fulcrumNetwork)"
                    )
                )
            }
            let merged = OpalBase.Network.ServerCatalogModel.makeMergedServers(
                primary: overrides,
                secondary: defaults,
                fallback: fallback
            )
            guard !merged.isEmpty else { throw SwiftFulcrum.Client.Error.transport(.setupFailed) }
            return merged
        })
    }
}

