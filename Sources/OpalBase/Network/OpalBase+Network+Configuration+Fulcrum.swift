// OpalBase+Network+Configuration+Fulcrum.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Configuration {
    var fulcrumBootstrapServers: [URL] {
        primaryFulcrumServers
    }
    
    func makeFulcrumServerCatalogRepository() -> SwiftFulcrum.ServerCatalog.Repository {
        let primaryServers = primaryFulcrumServers
        let expectedFulcrumNetwork = network.fulcrumNetwork
        
        return SwiftFulcrum.ServerCatalog.Repository(load: { fulcrumNetwork, fallback in
            guard fulcrumNetwork == expectedFulcrumNetwork else {
                throw SwiftFulcrum.Client.Error.client(
                    .protocolMismatch(
                        "FulcrumClient network mismatch. configuredEnvironment=\(network), expectedFulcrumNetwork=\(expectedFulcrumNetwork), requestedFulcrumNetwork=\(fulcrumNetwork)"
                    )
                )
            }
            let merged = OpalBase.Network.ServerCatalog.makeMergedServers(
                primary: primaryServers,
                fallback: fallback
            )
            guard !merged.isEmpty else { throw SwiftFulcrum.Client.Error.transport(.setupFailed) }
            return merged
        })
    }

    /// Keeps the configured endpoint set exact by ignoring every provider fallback catalog.
    func makeExactFulcrumServerCatalogRepository() -> SwiftFulcrum.ServerCatalog.Repository {
        .makeConstant(serverURLs)
    }

    private var primaryFulcrumServers: [URL] {
        if !serverURLs.isEmpty { return serverURLs }
        return serverCatalog.listServers(for: network)
    }
}
