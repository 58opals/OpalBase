// OpalBase+Account+MosaicPrivateAlphaRuntime+PrivateDeployment.swift

#if os(macOS)
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// App-visible protocol phase with no OpalFusion type in the application contract.
    @_spi(MosaicPrivateAlpha)
    public enum Phase: CaseIterable, Sendable, Equatable {
        case discovery
        case candidateSetAgreement
        case admission
        case controlRosterAgreement
        case roleElection
        case nonceAllocation
        case manifestAgreement
        case walletReservation
        case groupedCommitment
        case anonymousComponentSubmission
        case transcriptAgreement
        case bchSigning

        init(_ phase: OpalFusion.MosaicPrivateAlphaRuntime.Phase) {
            switch phase {
            case .discovery: self = .discovery
            case .candidateSetAgreement: self = .candidateSetAgreement
            case .admission: self = .admission
            case .controlRosterAgreement:
                self = .controlRosterAgreement
            case .roleElection: self = .roleElection
            case .nonceAllocation: self = .nonceAllocation
            case .manifestAgreement: self = .manifestAgreement
            case .walletReservation: self = .walletReservation
            case .groupedCommitment: self = .groupedCommitment
            case .anonymousComponentSubmission:
                self = .anonymousComponentSubmission
            case .transcriptAgreement: self = .transcriptAgreement
            case .bchSigning: self = .bchSigning
            }
        }
    }

    /// Stable result after the requested transition, exact persistence, and any required publication.
    @_spi(MosaicPrivateAlpha)
    public enum PrivateDeploymentProgress: Sendable, Equatable {
        case awaitingInput(Phase)
        case ignoredDuplicate(Phase)
        case awaitingAbortSignature(Phase)
        case terminal(TerminalEvidence)
    }

    /// App-owned effects required to make a private-deployment transition durable and publish it.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentCapabilities: Sendable {
        let recoveryPersistence: FusionRecoveryPersistence
        let relays: PrivateDeploymentRelayCapabilities

        @_spi(MosaicPrivateAlpha)
        public init(
            recoveryPersistence: FusionRecoveryPersistence,
            relays: PrivateDeploymentRelayCapabilities
        ) {
            self.recoveryPersistence = recoveryPersistence
            self.relays = relays
        }
    }

    /// Purpose-separated public blind-authorization keys committed by the conductor.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentManifestAuthorizationKeys: Sendable {
        let component: OpalCrypto.RSABSSA.VerificationKey
        let bchSignature: OpalCrypto.RSABSSA.VerificationKey

        @_spi(MosaicPrivateAlpha)
        public init(
            component: OpalCrypto.RSABSSA.VerificationKey,
            bchSignature: OpalCrypto.RSABSSA.VerificationKey
        ) {
            self.component = component
            self.bchSignature = bchSignature
        }

        var fusionKeys:
            OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentManifestAuthorizationKeys
        {
            .init(component: component, bchSignature: bchSignature)
        }
    }
}
#endif
