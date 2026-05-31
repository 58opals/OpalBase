// OpalBase+Network+Configuration~Fulcrum.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Configuration {
    var fulcrumBootstrapServers: [URL] {
        let overrides = OpalBase.Network.ServerCatalog.makeNormalizedServers(serverURLs)
        if !overrides.isEmpty { return overrides }
        return serverCatalog.listServers(for: network)
    }
    
    func makeFulcrumServerCatalogRepository() -> SwiftFulcrum.ServerCatalog.Repository {
        let overrides = OpalBase.Network.ServerCatalog.makeNormalizedServers(serverURLs)
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
            let primaryCatalog = overrides.isEmpty ? defaults : overrides
            let merged = OpalBase.Network.ServerCatalog.makeMergedServers(
                primary: primaryCatalog,
                fallback: fallback
            )
            guard !merged.isEmpty else { throw SwiftFulcrum.Client.Error.transport(.setupFailed) }
            return merged
        })
    }
}
