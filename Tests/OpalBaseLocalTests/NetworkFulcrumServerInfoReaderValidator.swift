// NetworkFulcrumServerInfoReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.ServerInfoReader", .tags(.unit, .network))
struct NetworkFulcrumServerInfoReaderValidator {
    @Test("maps server info responses into OpalBase types")
    func fetchServerInfoMapsResponses() async throws {
        let expectedMinimumProtocolVersion = try #require(OpalBase.Network.ProtocolVersion(major: 1, minor: 4))
        let expectedMaximumProtocolVersion = try #require(OpalBase.Network.ProtocolVersion(major: 1, minor: 5))
        let client = try ServerInfoClientTestActor(
            versionResponse: try Self.makeVersionResponse(serverVersion: "Fulcrum 1.9.0", protocolVersion: "1.5"),
            featuresResponse: try Self.makeFeaturesResponse(),
            relayFeeResponse: try Self.makeRelayFeeResponse(fee: 0.00001),
            estimatedFeeResponse: try Self.makeEstimateFeeResponse(fee: 0.00002)
        )
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(client: client)

        try await reader.ping()
        let version = try await reader.fetchServerVersion(
            clientName: "OpalBase",
            minimumProtocolVersion: expectedMinimumProtocolVersion,
            maximumProtocolVersion: expectedMaximumProtocolVersion
        )
        let features = try await reader.fetchServerFeatures()
        let relayFee = try await reader.fetchRelayFee()
        let estimatedFee = try await reader.estimateFee(forConfirmationTarget: 6)

        #expect(version.serverVersion == "Fulcrum 1.9.0")
        #expect(version.negotiatedProtocolVersion == expectedMaximumProtocolVersion)
        #expect(features.genesisHash == String(repeating: "a", count: 64))
        #expect(features.serverVersion == "Fulcrum 1.9.0")
        #expect(features.minimumProtocolVersion == expectedMinimumProtocolVersion)
        #expect(features.maximumProtocolVersion == expectedMaximumProtocolVersion)
        #expect(features.hosts?["fulcrum.example.com"]?.secureWebSocketPort == 50004)
        #expect(features.hasCashTokens == true)
        #expect(features.reusablePaymentAddress?.startingHeight == 800_000)
        #expect(features.hasBroadcastPackageSupport == true)
        #expect(relayFee == 0.00001)
        #expect(estimatedFee == 0.00002)
    }

    @Test("protocol version parser rejects malformed components")
    func protocolVersionParserRejectsMalformedComponents() {
        #expect(OpalBase.Network.ProtocolVersion(string: "1.x.2") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "1..2") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "1.2.") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "+1.2") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "1.+2") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "01.2") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "1.02") == nil)
        #expect(OpalBase.Network.ProtocolVersion(string: "1.2.03") == nil)
        #expect(OpalBase.Network.ProtocolVersion(major: 1, minor: 2, patch: 3, isPatchComponentIncluded: false) == nil)
    }

    @Test("protocol version parser accepts canonical zero components")
    func protocolVersionParserAcceptsCanonicalZeroComponents() throws {
        let twoComponentVersion = try #require(OpalBase.Network.ProtocolVersion(string: "0.0"))
        let threeComponentVersion = try #require(OpalBase.Network.ProtocolVersion(string: "1.2.0"))

        #expect(twoComponentVersion.description == "0.0")
        #expect(threeComponentVersion.description == "1.2.0")
    }
    
    @Test("protocol version decoder rejects invalid components")
    func protocolVersionDecoderRejectsInvalidComponents() throws {
        let validVersion = try #require(OpalBase.Network.ProtocolVersion(major: 1, minor: 4))
        let encoded = try JSONEncoder().encode(validVersion)
        let decoded = try JSONDecoder().decode(OpalBase.Network.ProtocolVersion.self, from: encoded)
        #expect(decoded == validVersion)
        
        let invalidPayload = Data(#"{"major":-1,"minor":4,"patch":0,"isPatchComponentIncluded":false}"#.utf8)
        let context = try Self.captureDataCorruptedContext {
            _ = try JSONDecoder().decode(OpalBase.Network.ProtocolVersion.self, from: invalidPayload)
        }

        #expect(context.debugDescription == "Invalid protocol version components")
    }

    @Test("translates timeout failures for server info requests")
    func pingTranslatesTimeoutFailures() async throws {
        let client = try ServerInfoClientTestActor(
            pingError: SwiftFulcrum.Client.Error.client(.timeout(.seconds(3)))
        )
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(client: client)

        let failure = try await Self.captureNetworkError {
            try await reader.ping()
        }

        #expect(failure.reason == .timeout)
        #expect(failure.message == "Operation timed out")
        #expect(failure.metadata["timeoutSeconds"] == "3.0")
    }

    @Test("rejects negative server fee rates")
    func rejectsNegativeServerFeeRates() async throws {
        let relayReader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                relayFeeError: Self.makeDecodeError("Invalid relay fee: -1e-05")
            )
        )
        let relayFailure = try await Self.captureNetworkError {
            _ = try await relayReader.fetchRelayFee()
        }
        #expect(relayFailure.reason == .decoding)
        #expect(relayFailure.message == "Invalid relay fee: -1e-05")

        let estimateReader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                estimatedFeeError: Self.makeDecodeError("Invalid estimated fee: -1.0")
            )
        )
        let estimateFailure = try await Self.captureNetworkError {
            _ = try await estimateReader.estimateFee(forConfirmationTarget: 6)
        }
        #expect(estimateFailure.reason == .decoding)
        #expect(estimateFailure.message == "Invalid estimated fee: -1.0")
    }
    
    @Test("rejects non-positive fee confirmation targets")
    func rejectsNonPositiveFeeConfirmationTargets() async throws {
        let client = try ServerInfoClientTestActor()
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(client: client)
        
        let zeroFailure = try await Self.captureNetworkError {
            _ = try await reader.estimateFee(forConfirmationTarget: 0)
        }
        #expect(zeroFailure.reason == .encoding)
        #expect(zeroFailure.message == "Invalid fee confirmation target: 0")
        
        let negativeFailure = try await Self.captureNetworkError {
            _ = try await reader.estimateFee(forConfirmationTarget: -1)
        }
        #expect(negativeFailure.reason == .encoding)
        #expect(negativeFailure.message == "Invalid fee confirmation target: -1")
        
        #expect(await client.readEstimateFeeTargets().isEmpty)
    }
    
    @Test("rejects negative server feature pruning limits")
    func fetchServerFeaturesRejectsNegativePruningLimits() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Invalid server.features pruning: -1")
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature pruning limit: -1")
    }
    
    @Test("rejects invalid server feature host ports")
    func fetchServerFeaturesRejectsInvalidHostPorts() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Invalid server.features host ssl_port: -1")
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature ssl port: -1")
    }
    
    @Test("rejects negative reusable payment address metadata")
    func fetchServerFeaturesRejectsNegativeReusablePaymentAddressMetadata() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Invalid server.features rpa history_block_limit: -1")
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature rpa history block limit: -1")
    }
    
    @Test("rejects inconsistent reusable payment address prefix ranges")
    func fetchServerFeaturesRejectsInconsistentReusablePaymentAddressPrefixRanges() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Invalid server.features rpa prefix bit range: 17 exceeds 16")
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature rpa prefix range: minimum 17 exceeds indexed 16")
    }

    @Test("rejects reusable payment address prefix bits above the hash width")
    func fetchServerFeaturesRejectsReusablePaymentAddressPrefixBitsAboveHashWidth() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresResponse: Self.makeFeaturesResponse(
                    reusablePaymentAddress: Self.makeReusablePaymentAddressFeatures(prefixBits: 257)
                )
            )
        )

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature rpa indexed prefix bits: 257")

        let boundaryReader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresResponse: Self.makeFeaturesResponse(
                    reusablePaymentAddress: Self.makeReusablePaymentAddressFeatures(
                        prefixBits: 256,
                        minimumPrefixBits: 256
                    )
                )
            )
        )

        let boundaryFeatures = try await boundaryReader.fetchServerFeatures()

        #expect(boundaryFeatures.reusablePaymentAddress?.indexedPrefixBits == 256)
        #expect(boundaryFeatures.reusablePaymentAddress?.minimumPrefixBits == 256)
    }

    @Test("translates inconsistent server feature protocol ranges")
    func fetchServerFeaturesTranslatesInconsistentProtocolRanges() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Server feature protocol range is invalid: 1.5...1.4")
            )
        )

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature protocol range: minimum 1.5 exceeds maximum 1.4")
    }

    @Test("rejects malformed server feature genesis hashes")
    func fetchServerFeaturesRejectsMalformedGenesisHashes() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Expected block hash to be exactly 64 hex characters")
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Expected block hash to be exactly 64 hex characters")
        
        let prefixedReader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Expected block hash to contain only hex characters")
            )
        )
        
        let prefixedFailure = try await Self.captureNetworkError {
            _ = try await prefixedReader.fetchServerFeatures()
        }
        
        #expect(prefixedFailure.reason == .decoding)
        #expect(prefixedFailure.message == "Expected block hash to contain only hex characters")
    }
    
    @Test("rejects unsupported server feature hash functions")
    func fetchServerFeaturesRejectsUnsupportedHashFunctions() async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError("Unsupported server.features hash_function: sha1")
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Unsupported server feature hash function: sha1")
    }
}

extension NetworkFulcrumServerInfoReaderValidator {
    enum DataCorruptedContextCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    struct DecodeFailure: Swift.Error, CustomStringConvertible {
        let description: String
    }
    
    static func makeDecodeError(_ message: String) -> SwiftFulcrum.Client.Error {
        .coding(.decode(DecodeFailure(description: ".unexpectedFormat(\"\(message)\")")))
    }
    
    static func makeVersionResponse(
        serverVersion: String,
        protocolVersion: String
    ) throws -> SwiftFulcrum.Response.Server.Version {
        let payload = try JSONSerialization.data(withJSONObject: [serverVersion, protocolVersion])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Server.Version.self, from: payload)
    }

    static func makeFeaturesResponse(
        genesisHash: String = String(repeating: "a", count: 64),
        hashFunction: String = "sha256",
        pruningLimit: Int = 100,
        hosts: [String: [String: Int]] = [
            "fulcrum.example.com": ["ssl_port": 50002, "tcp_port": 50001, "ws_port": 50003, "wss_port": 50004]
        ],
        reusablePaymentAddress: [String: Int] = makeReusablePaymentAddressFeatures()
    ) throws -> SwiftFulcrum.Response.Server.Features {
        let payloadObject: [String: Any] = [
            "genesis_hash": genesisHash,
            "hash_function": hashFunction,
            "server_version": "Fulcrum 1.9.0",
            "protocol_max": "1.5",
            "protocol_min": "1.4",
            "pruning": pruningLimit,
            "hosts": hosts,
            "dsproof": true,
            "cashtokens": true,
            "rpa": reusablePaymentAddress,
            "broadcast_package": true
        ]
        let payload = try JSONSerialization.data(withJSONObject: payloadObject)
        return try JSONDecoder().decode(SwiftFulcrum.Response.Server.Features.self, from: payload)
    }

    static func makeReusablePaymentAddressFeatures(
        prefixBits: Int = 16,
        minimumPrefixBits: Int = 8
    ) -> [String: Int] {
        [
            "history_block_limit": 288,
            "max_history": 100,
            "prefix_bits": prefixBits,
            "prefix_bits_min": minimumPrefixBits,
            "starting_height": 800_000
        ]
    }

    static func makeRelayFeeResponse(
        fee: Double
    ) throws -> SwiftFulcrum.Response.Blockchain.RelayFee {
        let payload = try JSONEncoder().encode(fee)
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.RelayFee.self, from: payload)
    }

    static func makeEstimateFeeResponse(
        fee: Double
    ) throws -> SwiftFulcrum.Response.Blockchain.EstimateFee {
        let payload = try JSONEncoder().encode(fee)
        return try JSONDecoder().decode(SwiftFulcrum.Response.Blockchain.EstimateFee.self, from: payload)
    }

    static func captureDataCorruptedContext(
        _ work: () throws -> Void
    ) throws -> DecodingError.Context {
        do {
            try work()
            throw DataCorruptedContextCaptureFailure.didNotThrow
        } catch DecodingError.dataCorrupted(let context) {
            return context
        } catch let failure as DataCorruptedContextCaptureFailure {
            throw failure
        } catch {
            throw DataCorruptedContextCaptureFailure.unexpected(error)
        }
    }

    static func captureNetworkError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Network.Error {
        do {
            try await work()
            throw NetworkErrorCaptureFailure.didNotThrow
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch let failure as NetworkErrorCaptureFailure {
            throw failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
    }
}
