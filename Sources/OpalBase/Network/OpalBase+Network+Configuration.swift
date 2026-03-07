// OpalBase+Network+Configuration.swift

import Foundation

extension _OpalBase.Network {
    public struct Configuration: Sendable, Equatable {
        public var serverURLs: [URL]
        public var serverCatalog: ServerCatalogModel
        public var connectionTimeout: Duration
        public var maximumMessageSize: Int
        public var reconnectConfiguration: ReconnectConfiguration
        public var network: EnvironmentModel
        
        public init(
            serverURLs: [URL],
            serverCatalog: ServerCatalogModel = .opalDefault,
            connectionTimeout: Duration = .seconds(10),
            maximumMessageSize: Int = 64 * 1_024 * 1_024,
            reconnect: ReconnectConfiguration = .defaultValue,
            network: EnvironmentModel = .mainnet
        ) {
            self.serverURLs = ServerCatalogModel.makeNormalizedServers(serverURLs)
            self.serverCatalog = serverCatalog
            self.connectionTimeout = connectionTimeout
            self.maximumMessageSize = maximumMessageSize
            self.reconnectConfiguration = reconnect
            self.network = network
        }
    }
}
