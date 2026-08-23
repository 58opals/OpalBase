// MosaicPrivateAlphaApplicationFacadeConsumer.swift

#if os(macOS)
@_spi(MosaicPrivateAlpha) import OpalBase

/// Compile-only consumer gate for the application facade from a target that does not depend on OpalFusion.
public enum MosaicPrivateAlphaApplicationFacadeConsumer {
    public static func assertTransportBootstrapSurfaceCompiles() {
        typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

        _ = Runtime.PrivateDeploymentRole.self
        _ = Runtime.TransportBootstrapRoster.self
        _ = Runtime.TransportBootstrapAuthorizationKeyDocument.self
        _ = Runtime.TransportBootstrapAnonymousMailboxRequest.self
        _ = Runtime.TransportBootstrapControlMailboxClaim.self
        _ = Runtime.TransportBootstrapControlMailboxClaimSet.self
        _ = Runtime.TransportBootstrapBlindResponseSet.self
        _ = Runtime.TransportBootstrapAnonymousMailboxRegistration.self
        _ = Runtime.TransportBootstrapAnonymousMailboxAssignment.self
        _ = Runtime.TransportBootstrapConductorMailboxAssignment.self
        _ = Runtime.TransportBootstrapAnonymousMailboxRegistrationSet.self
        _ = Runtime.TransportBootstrapRegistrationSetAcknowledgement.self
        _ = Runtime.TransportBootstrapRegistrationSetAcknowledgementSet.self
        _ = Runtime.TransportBootstrapPublicationReceipt.self
        _ = Runtime.TransportBootstrapInboundEvent.self
        _ = Runtime.TransportBootstrapEventStream.self
        _ = Runtime.TransportBootstrapInbox.self
        _ = Runtime.TransportBootstrapOpenedDocument<
            Runtime.TransportBootstrapAuthorizationKeyDocument
        >.self
        _ = Runtime.TransportBootstrapLayerTimestamps.self
        _ = Runtime.Profile.self
        _ = Runtime.BroadcastApprovalRequest.self
        _ = Runtime.BroadcastApprovalRequest.ExpectedOutput.self
        _ = Runtime.ChainAttestation.self
        _ = Runtime.ChainClient.self
        let chainClientFactory: @Sendable (
            OpalBase.Network.Configuration
        ) async throws -> Runtime.ChainClient = Runtime
            .makeAttestedChainClient(configuration:)
        _ = chainClientFactory
    }
}
#endif
