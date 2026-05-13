// OpalBase+Network+Configuration.swift

import Foundation

extension _OpalBase.Network {
    public struct Configuration: Sendable, Equatable {
        private var normalizedServerURLs: [URL]
        public var serverURLs: [URL] {
            get { normalizedServerURLs }
            set { normalizedServerURLs = ServerCatalog.makeNormalizedServers(newValue) }
        }
        public var serverCatalog: ServerCatalog
        /// Time allowed to establish the WebSocket connection.
        /// This does not cap the lifetime of an established socket.
        public var connectTimeout: Duration
        public var maximumMessageSize: Int
        public var reconnectConfiguration: ReconnectConfiguration
        public var network: Environment
        
        public init(
            serverURLs: [URL],
            serverCatalog: ServerCatalog = .opalDefault,
            connectTimeout: Duration = .seconds(10),
            maximumMessageSize: Int = 64 * 1_024 * 1_024,
            reconnect: ReconnectConfiguration = .defaultValue,
            network: Environment = .mainnet
        ) {
            self.normalizedServerURLs = ServerCatalog.makeNormalizedServers(serverURLs)
            self.serverCatalog = serverCatalog
            self.connectTimeout = connectTimeout
            self.maximumMessageSize = maximumMessageSize
            self.reconnectConfiguration = reconnect
            self.network = network
        }

        @available(
            *,
            deprecated,
            renamed: "connectTimeout",
            message: "Use connectTimeout. It only bounds connection establishment and does not cap the lifetime of an established socket."
        )
        public var connectionTimeout: Duration {
            get { connectTimeout }
            set { connectTimeout = newValue }
        }

        @available(
            *,
            deprecated,
            message: "Use init(serverURLs:serverCatalog:connectTimeout:maximumMessageSize:reconnect:network:). connectionTimeout only bounds connection establishment and does not cap the lifetime of an established socket."
        )
        public init(
            serverURLs: [URL],
            serverCatalog: ServerCatalog = .opalDefault,
            connectionTimeout: Duration,
            maximumMessageSize: Int = 64 * 1_024 * 1_024,
            reconnect: ReconnectConfiguration = .defaultValue,
            network: Environment = .mainnet
        ) {
            self.init(
                serverURLs: serverURLs,
                serverCatalog: serverCatalog,
                connectTimeout: connectionTimeout,
                maximumMessageSize: maximumMessageSize,
                reconnect: reconnect,
                network: network
            )
        }
    }
}
