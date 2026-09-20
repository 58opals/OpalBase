// OpalBase+Account+MosaicPrivateAlphaRuntime+DiscoveryPreparation.swift

#if os(macOS)
import Foundation
import OpalCrypto
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Experimental preparation of canonical discovery documents and bounded admission work.
    /// The application owns fresh pool selection and review of relay operator labels.
    @_spi(MosaicPrivateAlpha)
    public struct DiscoveryPreparation: Sendable {
        @_spi(MosaicPrivateAlpha)
        public enum TimingProfile: String, Sendable, Equatable {
            case frozen = "nostr-tor/0-opal-mainnet-alpha-private-deployment.1"
            case bootstrap180Candidate = "nostr-tor/0-opal-mainnet-alpha-private-deployment-bootstrap180.1"

            fileprivate var fusionValue: OpalFusion.MosaicPrivateAlphaRuntime.DiscoveryPreparation.TimingProfile {
                switch self {
                case .frozen: .frozen
                case .bootstrap180Candidate: .bootstrap180Candidate
                }
            }
        }

        @_spi(MosaicPrivateAlpha)
        public enum PreparationFailure: Error, Sendable, Equatable {
            case invalidConfiguration
            case invalidSearchRange
        }

        @_spi(MosaicPrivateAlpha)
        public struct Relay: Sendable, Equatable {
            @_spi(MosaicPrivateAlpha) public let endpoint: String
            @_spi(MosaicPrivateAlpha) public let reviewedOperatorLabel: String

            @_spi(MosaicPrivateAlpha)
            public init(endpoint: String, reviewedOperatorLabel: String) {
                self.endpoint = endpoint
                self.reviewedOperatorLabel = reviewedOperatorLabel
            }
        }

        private let preparation: OpalFusion.MosaicPrivateAlphaRuntime.DiscoveryPreparation

        @_spi(MosaicPrivateAlpha) public var epochStartUnixSeconds: UInt64 { preparation.epochStartUnixSeconds }
        @_spi(MosaicPrivateAlpha) public var opaquePoolDocument: Data { preparation.opaquePoolDocument }
        @_spi(MosaicPrivateAlpha) public var relaySetDocument: Data { preparation.relaySetDocument }
        @_spi(MosaicPrivateAlpha) public var relaySetDigest: Data { preparation.relaySetDigest }
        @_spi(MosaicPrivateAlpha) public var relayEndpointIdentifiers: [String] { preparation.relayEndpointIdentifiers }
        @_spi(MosaicPrivateAlpha) public var relayOperatorDigests: [Data] { preparation.relayOperatorDigests }
        @_spi(MosaicPrivateAlpha) public var beaconCutoffUnixSeconds: UInt64 { preparation.beaconCutoffUnixSeconds }

        @_spi(MosaicPrivateAlpha)
        public init(
            epochStartUnixSeconds: UInt64,
            appGeneratedOpaquePoolIdentifier: Data,
            relays: [Relay],
            timingProfile: TimingProfile = .frozen
        ) throws {
            do {
                preparation = try .init(
                    epochStartUnixSeconds: epochStartUnixSeconds,
                    appGeneratedOpaquePoolIdentifier: appGeneratedOpaquePoolIdentifier,
                    relays: relays.map { .init(endpoint: $0.endpoint, reviewedOperatorLabel: $0.reviewedOperatorLabel) },
                    timingProfile: timingProfile.fusionValue
                )
            } catch {
                throw PreparationFailure.invalidConfiguration
            }
        }

        /// Returns a valid nonce in this bounded batch, or nil. No network or wallet access.
        // Preserve Base's framework call boundary: an optimized application
        // must not acquire a direct link to the implementation-only dependency.
        @inline(never)
        @_spi(MosaicPrivateAlpha)
        public func findAvailabilityNonce(
            discoveryVerificationKey: OpalCrypto.Signature.BIP340.VerificationKey,
            startingAt firstNonce: UInt64,
            count: UInt32
        ) throws -> UInt64? {
            do {
                return try preparation.findAvailabilityNonce(
                    discoveryVerificationKey: discoveryVerificationKey,
                    startingAt: firstNonce,
                    count: count
                )
            } catch {
                throw PreparationFailure.invalidSearchRange
            }
        }

        /// Receives bounded public formation events; the session owner still
        /// authenticates their pool, roster, phase and durable transition.
        @_spi(MosaicPrivateAlpha)
        public func makeInbox(
            binding: Binding,
            capabilities: PrivateDeploymentRelayCapabilities,
            maximumEventCount: Int = 256,
            currentUnixSeconds: @escaping @Sendable () -> UInt64 = {
                UInt64(Date().timeIntervalSince1970)
            }
        ) throws -> PrivateDeploymentInbox {
            do {
                return .init(try .init(
                    preparation: preparation,
                    binding: binding.fusionBinding,
                    capabilities: capabilities.fusionCapabilities(),
                    maximumEventCount: maximumEventCount,
                    currentUnixSeconds: currentUnixSeconds
                ))
            } catch {
                throw Failure(error)
            }
        }
    }
}
#endif
