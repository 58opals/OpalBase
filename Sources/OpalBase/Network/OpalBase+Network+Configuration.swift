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
        public var maximumMessageSize: Int {
            didSet {
                maximumMessageSize = Self.clampedMaximumMessageSize(maximumMessageSize)
            }
        }
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
            self.maximumMessageSize = Self.clampedMaximumMessageSize(maximumMessageSize)
            self.reconnectConfiguration = reconnect
            self.network = network
        }

        private static func clampedMaximumMessageSize(_ maximumMessageSize: Int) -> Int {
            max(1, maximumMessageSize)
        }
    }
}
