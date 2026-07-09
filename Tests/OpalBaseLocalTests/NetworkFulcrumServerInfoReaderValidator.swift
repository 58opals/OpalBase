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
            featuresResponse: try Self.makeFeaturesResponse(genesisHash: String(repeating: "A", count: 64)),
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

    @Test(
        "protocol version parser rejects malformed components",
        arguments: malformedProtocolVersionInputs
    )
    func protocolVersionParserRejectsMalformedComponents(_ input: String) {
        #expect(OpalBase.Network.ProtocolVersion(string: input) == nil)
    }

    @Test("protocol version parser rejects hidden patch components")
    func protocolVersionParserRejectsHiddenPatchComponents() {
        #expect(OpalBase.Network.ProtocolVersion(major: 1, minor: 2, patch: 3, isPatchComponentIncluded: false) == nil)
    }

    @Test(
        "protocol version parser accepts canonical zero components",
        arguments: canonicalZeroProtocolVersionCases
    )
    func protocolVersionParserAcceptsCanonicalZeroComponents(
        versionCase: (input: String, expectedDescription: String)
    ) throws {
        let version = try #require(OpalBase.Network.ProtocolVersion(string: versionCase.input))

        #expect(version.description == versionCase.expectedDescription)
    }

    private static let canonicalZeroProtocolVersionCases = [
        (input: "0.0", expectedDescription: "0.0"),
        (input: "1.2.0", expectedDescription: "1.2.0")
    ]

    private static let malformedProtocolVersionInputs = [
        "1.x.2",
        "1..2",
        "1.2.",
        "+1.2",
        "1.+2",
        "01.2",
        "1.02",
        "1.2.03"
    ]

    private static let malformedGenesisHashCases = [
        (
            decodeMessage: "Expected block hash to be exactly 64 hex characters",
            expectedMessage: "Expected block hash to be exactly 64 hex characters"
        ),
        (
            decodeMessage: "Expected block hash to contain only hex characters",
            expectedMessage: "Expected block hash to contain only hex characters"
        )
    ]

    private static let serverFeatureDecodingFailureCases = [
        (
            decodeMessage: "Invalid server.features pruning: -1",
            expectedMessage: "Invalid server feature pruning limit: -1"
        ),
        (
            decodeMessage: "Invalid server.features host ssl_port: -1",
            expectedMessage: "Invalid server feature ssl port: -1"
        ),
        (
            decodeMessage: "Invalid server.features rpa history_block_limit: -1",
            expectedMessage: "Invalid server feature rpa history block limit: -1"
        ),
        (
            decodeMessage: "Invalid server.features rpa prefix bit range: 17 exceeds 16",
            expectedMessage: "Invalid server feature rpa prefix range: minimum 17 exceeds indexed 16"
        ),
        (
            decodeMessage: "Server feature protocol range is invalid: 1.5...1.4",
            expectedMessage: "Invalid server feature protocol range: minimum 1.5 exceeds maximum 1.4"
        )
    ]

    private static let invalidFeeConfirmationTargetCases = [
        (target: 0, expectedMessage: "Invalid fee confirmation target: 0"),
        (target: -1, expectedMessage: "Invalid fee confirmation target: -1")
    ]

    private static let malformedServerFeatureHostNames = [
        "bad_host.example.com",
        "-leading.example.com",
        "trailing-.example.com",
        "empty..example.com",
        "\(String(repeating: "a", count: 64)).example.com"
    ]

    enum NegativeServerFeeRateCase: CaseIterable, Sendable {
        case relay
        case estimated

        var decodeMessage: String {
            switch self {
            case .relay:
                return "Invalid relay fee: -1e-05"
            case .estimated:
                return "Invalid estimated fee: -1.0"
            }
        }
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

    @Test(
        "rejects negative server fee rates",
        arguments: NegativeServerFeeRateCase.allCases
    )
    func rejectsNegativeServerFeeRates(_ feeCase: NegativeServerFeeRateCase) async throws {
        let failure: OpalBase.Network.Error
        switch feeCase {
        case .relay:
            let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
                client: try ServerInfoClientTestActor(
                    relayFeeError: Self.makeDecodeError(feeCase.decodeMessage)
                )
            )
            failure = try await Self.captureNetworkError {
                _ = try await reader.fetchRelayFee()
            }
        case .estimated:
            let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
                client: try ServerInfoClientTestActor(
                    estimatedFeeError: Self.makeDecodeError(feeCase.decodeMessage)
                )
            )
            failure = try await Self.captureNetworkError {
                _ = try await reader.estimateFee(forConfirmationTarget: 6)
            }
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == feeCase.decodeMessage)
    }
    
    @Test(
        "rejects non-positive fee confirmation targets",
        arguments: invalidFeeConfirmationTargetCases
    )
    func rejectsNonPositiveFeeConfirmationTargets(
        _ targetCase: (target: Int, expectedMessage: String)
    ) async throws {
        let client = try ServerInfoClientTestActor()
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(client: client)
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.estimateFee(forConfirmationTarget: targetCase.target)
        }
        #expect(failure.reason == .encoding)
        #expect(failure.message == targetCase.expectedMessage)
        
        #expect(await client.readEstimateFeeTargets().isEmpty)
    }
    
    @Test(
        "translates server feature decoding failures",
        arguments: serverFeatureDecodingFailureCases
    )
    func fetchServerFeaturesTranslatesDecodingFailures(
        _ failureCase: (decodeMessage: String, expectedMessage: String)
    ) async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError(failureCase.decodeMessage)
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == failureCase.expectedMessage)
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

    @Test(
        "rejects malformed server feature genesis hashes",
        arguments: malformedGenesisHashCases
    )
    func fetchServerFeaturesRejectsMalformedGenesisHashes(
        _ genesisHashCase: (decodeMessage: String, expectedMessage: String)
    ) async throws {
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresError: Self.makeDecodeError(genesisHashCase.decodeMessage)
            )
        )
        
        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == genesisHashCase.expectedMessage)
    }

    @Test(
        "rejects malformed server feature hosts",
        arguments: malformedServerFeatureHostNames
    )
    func fetchServerFeaturesRejectsMalformedHosts(hostName: String) async throws {
        let reader = try Self.makeServerFeaturesReader(hosts: [
            hostName: ["ssl_port": 50002]
        ])

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid server feature host: \(hostName)")
    }

    @Test("normalizes server feature hosts to lowercase")
    func fetchServerFeaturesNormalizesHostsToLowercase() async throws {
        let reader = try Self.makeServerFeaturesReader(hosts: [
            "Fulcrum.Example.com": ["ssl_port": 50002, "wss_port": 50004]
        ])

        let features = try await reader.fetchServerFeatures()

        #expect(features.hosts?["fulcrum.example.com"]?.secureWebSocketPort == 50004)
        #expect(features.hosts?["Fulcrum.Example.com"] == nil)
    }

    @Test("rejects duplicate server feature hosts after canonicalization")
    func fetchServerFeaturesRejectsDuplicateCanonicalHosts() async throws {
        let reader = try Self.makeServerFeaturesReader(hosts: [
            "Fulcrum.Example.com": ["ssl_port": 50002],
            "fulcrum.example.com": ["wss_port": 50004]
        ])

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchServerFeatures()
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Duplicate server feature host: fulcrum.example.com")
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

    static func makeServerFeaturesReader(
        hosts: [String: [String: Int]]
    ) throws -> OpalBase.Network.Fulcrum.ServerInfoReader {
        OpalBase.Network.Fulcrum.ServerInfoReader(
            client: try ServerInfoClientTestActor(
                featuresResponse: Self.makeFeaturesResponse(hosts: hosts)
            )
        )
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
