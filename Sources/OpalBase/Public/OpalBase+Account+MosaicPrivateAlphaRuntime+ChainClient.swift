// OpalBase+Account+MosaicPrivateAlphaRuntime+ChainClient.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact reviewed endpoint set and fresh genesis observation for one Fulcrum client.
    @_spi(MosaicPrivateAlpha)
    public struct ChainAttestation: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha)
        public let network: OpalBase.Network.Environment

        @_spi(MosaicPrivateAlpha)
        public let genesisHash: Data

        @_spi(MosaicPrivateAlpha)
        public let serverURLs: [URL]

        init(
            network: OpalBase.Network.Environment,
            genesisHash: Data,
            serverURLs: [URL]
        ) {
            self.network = network
            self.genesisHash = Data(genesisHash)
            self.serverURLs = serverURLs
        }
    }

    /// Opaque broadcast and exact-presence capability proven against one concrete Fulcrum client.
    @_spi(MosaicPrivateAlpha)
    public struct ChainClient: Sendable {
        @_spi(MosaicPrivateAlpha)
        public let attestation: ChainAttestation

        let networkClient: OpalBase.Account
            .MosaicNetworkAttestedTransactionClient

        init(
            attestation: ChainAttestation,
            networkClient: OpalBase.Account
                .MosaicNetworkAttestedTransactionClient
        ) {
            self.attestation = attestation
            self.networkClient = networkClient
        }
    }

    /// Creates one exact-endpoint Fulcrum client and freshly attests it before any chain I/O.
    @_spi(MosaicPrivateAlpha)
    public static func makeAttestedChainClient(
        configuration: OpalBase.Network.Configuration
    ) async throws -> ChainClient {
        _ = try validatedPrivateAlphaServerURLs(
            configuration: configuration
        )
        let fulcrumClient: OpalBase.Network.Fulcrum.Client
        do {
            fulcrumClient = try await .init(
                privateAlphaConfiguration: configuration
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw Failure.broadcastUnavailable
        }
        let features: OpalBase.Network.FulcrumServerFeatures
        do {
            features = try await OpalBase.Network.Fulcrum.ServerInfoReader(
                client: fulcrumClient
            ).fetchServerFeatures()
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw Failure.broadcastUnavailable
        }
        let attestation = try validateChainAttestation(
            configuration: configuration,
            features: features
        )
        return .init(
            attestation: attestation,
            networkClient: .init(
                OpalBase.Network.Fulcrum.TransactionClient(
                    client: fulcrumClient
                )
            )
        )
    }

    static func validateChainAttestation(
        configuration: OpalBase.Network.Configuration,
        features: OpalBase.Network.FulcrumServerFeatures
    ) throws -> ChainAttestation {
        let serverURLs = try validatedPrivateAlphaServerURLs(
            configuration: configuration
        )
        guard let genesisHash = try? Data(
                hexadecimalString: features.genesisHash
              ),
              genesisHash == Data(configuration.network.mosaicGenesisHash)
        else {
            throw Failure.invalidNetworkBinding
        }
        return .init(
            network: configuration.network,
            genesisHash: genesisHash,
            serverURLs: serverURLs
        )
    }

    private static func validatedPrivateAlphaServerURLs(
        configuration: OpalBase.Network.Configuration
    ) throws -> [URL] {
        let serverURLs = configuration.serverURLs.sorted {
            $0.absoluteString < $1.absoluteString
        }
        guard configuration.network == .mainnet,
              serverURLs.isEmpty == false,
              serverURLs.allSatisfy(isPermittedPrivateAlphaServerURL) else {
            throw Failure.invalidNetworkBinding
        }
        return serverURLs
    }

    private static func isPermittedPrivateAlphaServerURL(
        _ url: URL
    ) -> Bool {
        if url.scheme == "wss" { return true }
        guard url.scheme == "ws", let host = url.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
#endif
