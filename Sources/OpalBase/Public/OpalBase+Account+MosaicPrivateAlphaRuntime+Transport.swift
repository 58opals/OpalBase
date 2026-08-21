// OpalBase+Account+MosaicPrivateAlphaRuntime+Transport.swift

#if os(macOS)
@_exported @_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// App-owned WebSocket capability already constrained to one Tor-only route.
    @_spi(MosaicPrivateAlpha)
    public typealias TorWebSocketConnection = OpalFusion
        .MosaicPrivateAlphaRuntime.TorWebSocketConnection

    /// Exact text or binary payload received from a Tor-only WebSocket route.
    @_spi(MosaicPrivateAlpha)
    public typealias TorWebSocketMessage = OpalFusion
        .MosaicPrivateAlphaRuntime.TorWebSocketMessage

    /// Package-owned request for one exact set of endpoint-bound Tor routes.
    @_spi(MosaicPrivateAlpha)
    public typealias TransportBootstrapRouteRequest = OpalFusion
        .MosaicPrivateAlphaRuntime.TransportBootstrapRouteRequest

    /// One endpoint-bound Tor connection with app-attested isolation identity.
    @_spi(MosaicPrivateAlpha)
    public typealias PostManifestProvisionedRoute = OpalFusion
        .MosaicPrivateAlphaRuntime.PostManifestProvisionedRoute

    /// One exact gift-wrap publication prepared for durable relay delivery.
    @_spi(MosaicPrivateAlpha)
    public typealias TransportBootstrapPublication = OpalFusion
        .MosaicPrivateAlphaRuntime.TransportBootstrapPublication

    /// Durable replay and wrapper-freshness evidence for reconnect recovery.
    @_spi(MosaicPrivateAlpha)
    public typealias TransportBootstrapReplayEntry = OpalFusion
        .MosaicPrivateAlphaRuntime.TransportBootstrapReplayEntry

    /// App-owned Tor route construction accepted by the protocol runtime.
    @_spi(MosaicPrivateAlpha)
    public typealias TransportBootstrapRelayCapabilities = OpalFusion
        .MosaicPrivateAlphaRuntime.TransportBootstrapRelayCapabilities

    /// Relay delivery capabilities bound to durable acceptance recording.
    @_spi(MosaicPrivateAlpha)
    public typealias TransportBootstrapPublicationCapabilities = OpalFusion
        .MosaicPrivateAlphaRuntime.TransportBootstrapPublicationCapabilities
}
#endif
