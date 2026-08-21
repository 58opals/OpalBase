// MosaicPrivateAlphaApplicationFacadeConsumer.swift

#if os(macOS)
@_spi(MosaicPrivateAlpha) import OpalBase

/// Compile-only consumer gate for the application facade from a target that does not depend on OpalFusion.
public enum MosaicPrivateAlphaApplicationFacadeConsumer {
    public static func assertTransportBootstrapSurfaceCompiles() {
        typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

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
    }
}
#endif
