// DiagnosticsErrorPresentationValidator.swift

import Foundation
import OpalDiagnostics
import OpalBaseTestSupport
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("Diagnostics error presentation", .tags(.unit, .network))
struct DiagnosticsErrorPresentationValidator {
    private static var wrappedNetworkCancellationError: SwiftFulcrum.Client.Error {
        SwiftFulcrum.Client.Error.client(.unknown(OpalBase.Network.Error(reason: .cancelled)))
    }

    @Test(
        "network error reasons map to stable diagnostic codes",
        arguments: NetworkReasonClassificationCase.allCases
    )
    func verifyNetworkErrorReasonMapsToStableDiagnosticCode(
        classificationCase: NetworkReasonClassificationCase
    ) {
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: classificationCase.error) == classificationCase.expectedCode)
    }

    @Test(
        "network errors provide stable localized display and debug text",
        arguments: NetworkDisplayCase.allCases
    )
    func verifyNetworkErrorProvidesStableLocalizedDisplayAndDebugText(
        displayCase: NetworkDisplayCase
    ) {
        let expectation = displayCase.displayExpectation
        let error = expectation.error
        let description = String(describing: error)
        #expect((error as Swift.Error).localizedDescription == description)
        #expect(String(reflecting: error) == description)
        #expect(!description.contains("error 1"))
    }

    @Test(
        "network error display text includes expected substrings",
        arguments: networkDisplaySubstringCases
    )
    func verifyNetworkErrorDisplayTextIncludesExpectedSubstring(
        substringCase: NetworkDisplaySubstringCase
    ) {
        let expectation = substringCase.displayCase.displayExpectation
        let description = String(describing: expectation.error)
        #expect(description.contains(substringCase.expectedSubstring))
    }

    private static let networkDisplaySubstringCases: [NetworkDisplaySubstringCase] = NetworkDisplayCase.allCases.flatMap { displayCase in
        displayCase.displayExpectation.expectedSubstrings.map { expectedSubstring in
            NetworkDisplaySubstringCase(
                displayCase: displayCase,
                expectedSubstring: expectedSubstring
            )
        }
    }

    @Test(
        "network error display text redacts wallet identifying message values",
        arguments: NetworkDisplayRedactionCase.allCases
    )
    func verifyNetworkErrorDisplayTextRedactsWalletIdentifyingMessageValue(
        redactionCase: NetworkDisplayRedactionCase
    ) {
        let expectation = redactionCase.displayRedactionExpectation
        let error = OpalBase.Network.Error(
            reason: .transport,
            message: "Failed \(expectation.sensitiveValue)",
            metadata: [
                "closeCode": "1001",
                "serverURL": expectation.sensitiveValue
            ]
        )
        let description = (error as Swift.Error).localizedDescription

        #expect(description.contains(expectation.expectedToken))
        #expect(description.contains("closeCode=1001"))
        #expect(!description.contains("serverURL"))
        #expect(!description.contains(expectation.sensitiveValue))
    }

    @Test(
        "Fulcrum translator preserves recoverable transport detail",
        arguments: FulcrumTranslationCase.allCases
    )
    func verifyFulcrumTranslatorPreservesRecoverableTransportDetail(
        translationCase: FulcrumTranslationCase
    ) {
        let expectation = translationCase.translationExpectation
        #expect(OpalBase.Network.FulcrumErrorTranslator.translate(expectation.input) == expectation.expected)
    }

    @Test(
        "direct Fulcrum error classification uses translated network codes",
        arguments: FulcrumClassificationCase.allCases
    )
    func verifyDirectFulcrumErrorClassificationUsesTranslatedNetworkCodes(
        classificationCase: FulcrumClassificationCase
    ) {
        let translated = OpalBase.Network.FulcrumErrorTranslator.translate(classificationCase.error)
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: classificationCase.error) == classificationCase.expectedCode)
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: translated) == classificationCase.expectedCode)
    }

    @Test(
        "cancellation helpers recognize cancellation forms",
        arguments: CancellationRecognitionCase.allCases
    )
    func verifyCancellationHelpersRecognizeCancellationForms(
        recognitionCase: CancellationRecognitionCase
    ) {
        #expect(OpalBaseCancellation.isCancellationError(recognitionCase.error) == recognitionCase.expectedResult)
        #expect(recognitionCase.error.isCancellationError == recognitionCase.expectedResult)
    }

    @Test(
        "network failure equivalence ignores dynamic diagnostic identifiers",
        arguments: DynamicDiagnosticIdentifierCase.allCases
    )
    func ignoreDynamicDiagnosticIdentifiersInNetworkFailureEquivalence(
        identifierCase: DynamicDiagnosticIdentifierCase
    ) throws {
        switch identifierCase {
        case .translatedRequestIdentifier:
            let firstRequestID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
            let secondRequestID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

            #expect(OpalBase.Network.areFailuresEquivalent(
                SwiftFulcrum.Client.Error.client(.emptyResponse(firstRequestID)),
                SwiftFulcrum.Client.Error.client(.emptyResponse(secondRequestID))
            ))
        case .serverIdentifier:
            #expect(OpalBase.Network.areFailuresEquivalent(
                OpalBase.Network.Error(
                    reason: .server(code: -32000),
                    message: "Server overloaded",
                    metadata: ["serverIdentifier": "server-a"]
                ),
                OpalBase.Network.Error(
                    reason: .server(code: -32000),
                    message: "Server overloaded",
                    metadata: ["serverIdentifier": "server-b"]
                )
            ))
        }
    }

    @Test("network failure equivalence keeps stable metadata significant")
    func keepStableMetadataInNetworkFailureEquivalence() {
        #expect(!OpalBase.Network.areFailuresEquivalent(
            OpalBase.Network.Error(
                reason: .timeout,
                message: "Operation timed out",
                metadata: ["timeoutSeconds": "1.0"]
            ),
            OpalBase.Network.Error(
                reason: .timeout,
                message: "Operation timed out",
                metadata: ["timeoutSeconds": "2.0"]
            )
        ))
    }

    @Test("network failure equivalence normalizes stable diagnostic metadata")
    func normalizeStableDiagnosticMetadataInNetworkFailureEquivalence() {
        #expect(OpalBase.Network.areFailuresEquivalent(
            OpalBase.Network.Error(
                reason: .timeout,
                message: "Operation timed out",
                metadata: ["timeoutSeconds": "03"]
            ),
            OpalBase.Network.Error(
                reason: .timeout,
                message: "Operation timed out",
                metadata: ["timeoutSeconds": "3.0"]
            )
        ))
    }

    @Test("network diagnostics fields expose safe metadata and keep identifiers private")
    func verifyNetworkDiagnosticsFieldsExposeSafeMetadataAndKeepIdentifiersPrivate() throws {
        let error = OpalBase.Network.Error(
            reason: .transport,
            message: "Connection closed",
            metadata: [
                "closeCode": "1001",
                "timeoutSeconds": "03",
                "serverIdentifier": "server-123",
                "requestIdentifier": "request\n456",
                "request\nIdentifier": "custom\nrequest",
                " \n ": "orphan"
            ]
        )
        let fields = OpalDiagnostics.Field.errorFields(for: error)

        #expect(try Self.requireFieldValue(OpalDiagnostics.Field.Name.errorCode, in: fields) == OpalDiagnostics.ErrorCode.networkTransport.rawValue)
        #expect(try Self.requireFieldValue(OpalDiagnostics.Field.Name.errorReason, in: fields) == "transport")
        #expect(try Self.requireFieldValue(OpalDiagnostics.Field.Name.errorMessage, in: fields) == error.description)
        #expect(try Self.requireFieldValue(OpalDiagnostics.Field.Name.closeCode, in: fields) == "1001")
        #expect(try Self.requireFieldValue(OpalDiagnostics.Field.Name.timeoutSeconds, in: fields) == "3.0")
        #expect(try Self.requireField(OpalDiagnostics.Field.Name.errorMessage, in: fields).privacy == .private)
        #expect(try Self.requireField(OpalDiagnostics.Field.Name.closeCode, in: fields).privacy == .public)
        #expect(!fields.contains { $0.name == "serverIdentifier" })
        #expect(!fields.contains { $0.name == "requestIdentifier" })

        #expect(Self.findPrivateMetadataFields(in: fields).allSatisfy { $0.privacy == .private })
        #expect(Self.makePrivateMetadataValueSet(in: fields) == [
            "metadata=orphan",
            "request Identifier=custom request",
            "requestIdentifier=request 456",
            "serverIdentifier=server-123"
        ])
    }

    @Test(
        "generic localized diagnostics messages normalize blank and multiline text",
        arguments: GenericLocalizedMessageCase.allCases
    )
    func verifyGenericLocalizedDiagnosticsMessagesNormalizeBlankAndMultilineText(
        messageCase: GenericLocalizedMessageCase
    ) throws {
        let fields = OpalDiagnostics.Field.errorFields(for: messageCase.error)

        #expect(try Self.requireFieldValue(OpalDiagnostics.Field.Name.errorMessage, in: fields) == messageCase.expectedMessage)
    }

    @Test(
        "network diagnostics keep unsafe allowlisted metadata values private",
        arguments: AllowlistedMetadataVisibilityCase.allCases
    )
    func verifyNetworkDiagnosticsKeepUnsafeAllowlistedMetadataValuesPrivate(
        metadataCase: AllowlistedMetadataVisibilityCase
    ) throws {
        let expectation = metadataCase.diagnosticMetadataExpectation
        let error = OpalBase.Network.Error(
            reason: .transport,
            message: "Connection closed",
            metadata: [expectation.key: expectation.value]
        )
        let fields = OpalDiagnostics.Field.errorFields(for: error)

        if let publicValue = expectation.publicValue {
            #expect(try Self.requireFieldValue(expectation.publicFieldName, in: fields) == publicValue)
        } else {
            #expect(Self.findField(expectation.publicFieldName, in: fields) == nil)
        }

        #expect(Self.findPrivateMetadataFields(in: fields).allSatisfy { $0.privacy == .private })
        #expect(Self.makePrivateMetadataValueSet(in: fields) == expectation.privateMetadataValues)
    }

    @Test(
        "public OpalBase error domains classify through diagnostics",
        arguments: OpalBaseErrorDomainClassificationCase.allCases
    )
    func verifyPublicOpalBaseErrorDomainClassifiesThroughDiagnostics(
        classificationCase: OpalBaseErrorDomainClassificationCase
    ) {
        let expectation = classificationCase.diagnosticsClassificationExpectation
        #expect(
            OpalDiagnostics.ErrorCode.opalBaseCode(for: expectation.error) ==
                expectation.expectedCode
        )
    }

    private static func findField(
        _ name: String,
        in fields: [OpalDiagnostics.Field]
    ) -> OpalDiagnostics.Field? {
        fields.first { $0.name == name }
    }

    private static func requireField(
        _ name: String,
        in fields: [OpalDiagnostics.Field]
    ) throws -> OpalDiagnostics.Field {
        try #require(findField(name, in: fields))
    }

    private static func requireFieldValue(
        _ name: String,
        in fields: [OpalDiagnostics.Field]
    ) throws -> String {
        try requireField(name, in: fields).value
    }

    private static func findPrivateMetadataFields(
        in fields: [OpalDiagnostics.Field]
    ) -> [OpalDiagnostics.Field] {
        fields.filter { $0.name == OpalDiagnostics.Field.Name.privateErrorMetadata }
    }

    private static func makePrivateMetadataValueSet(
        in fields: [OpalDiagnostics.Field]
    ) -> Set<String> {
        Set(findPrivateMetadataFields(in: fields).map(\.value))
    }

    private struct DescribedError: Swift.Error, CustomStringConvertible {
        let description: String
    }

    private struct LocalizedDescriptionError: LocalizedError {
        let description: String

        var errorDescription: String? { description }
    }

    enum DynamicDiagnosticIdentifierCase: CaseIterable, Sendable {
        case translatedRequestIdentifier
        case serverIdentifier
    }

    enum NetworkDisplayRedactionCase: CaseIterable, Sendable {
        case webSocketURL
        case singleCharacterSchemeURL
        case unsupportedSchemeURL
        case hostEndpoint
        case singleDigitPortEndpoint
        case localEndpoint
        case ipv4Endpoint
        case ipv6Endpoint
        case requestIdentifier
        case cashAddress
        case cashAddressWithoutPrefix
        case legacyAddress
        case walletImportFormatPrivateKey
        case transactionIdentifier
        case rawPayload

        var displayRedactionExpectation: (sensitiveValue: String, expectedToken: String) {
            switch self {
            case .webSocketURL:
                return ("wss://private.example/socket", "[redacted-url]")
            case .singleCharacterSchemeURL:
                return ("x://private.example/socket", "[redacted-url]")
            case .unsupportedSchemeURL:
                return ("ftp://private.example/file", "[redacted-url]")
            case .hostEndpoint:
                return ("private.example:50002", "[redacted-endpoint]")
            case .singleDigitPortEndpoint:
                return ("private.example:9", "[redacted-endpoint]")
            case .localEndpoint:
                return ("localhost:50002", "[redacted-endpoint]")
            case .ipv4Endpoint:
                return ("192.0.2.1:50002", "[redacted-endpoint]")
            case .ipv6Endpoint:
                return ("[2001:db8::1]:50002", "[redacted-endpoint]")
            case .requestIdentifier:
                return ("123E4567-E89B-12D3-A456-426614174000", "[redacted-identifier]")
            case .cashAddress:
                return ("bitcoincash:qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqp4z5utj", "[redacted-address]")
            case .cashAddressWithoutPrefix:
                return (String(repeating: "q", count: 42), "[redacted-address]")
            case .legacyAddress:
                return ("1BoatSLRHtKNngkdXEeobR76b53LETtpyT", "[redacted-address]")
            case .walletImportFormatPrivateKey:
                return ("L1aW4aubDFB7yfras2S1mMEYCI6fr9DqHNLieyVy2gByX4mbmKvr", "[redacted-private-key]")
            case .transactionIdentifier:
                return (String(repeating: "a", count: 64), "[redacted-identifier]")
            case .rawPayload:
                return (String(repeating: "b", count: 128), "[redacted-identifier]")
            }
        }
    }

    enum NetworkDisplayCase: CaseIterable, Sendable {
        case transport
        case network
        case multilineNetwork
        case server
        case cancelled
        case timeout
        case protocolViolation
        case encoding
        case decoding
        case unknown
        case blankMessage

        var displayExpectation: (error: OpalBase.Network.Error, expectedSubstrings: [String]) {
            switch self {
            case .transport:
                return (
                    .init(reason: .transport, message: "Connection closed", metadata: ["closeCode": "1001"]),
                    ["Network transport error", "Connection closed", "reason=transport", "closeCode=1001"]
                )
            case .network:
                return (
                    .init(reason: .network, message: "TLS negotiation failed"),
                    ["Network connection error", "TLS negotiation failed", "reason=network"]
                )
            case .multilineNetwork:
                return (
                    .init(reason: .network, message: "TLS\nnegotiation\tfailed"),
                    ["Network connection error", "TLS negotiation failed", "reason=network"]
                )
            case .server:
                return (
                    .init(reason: .server(code: -5), message: "missing transaction"),
                    ["Network server error", "missing transaction", "reason=server", "serverCode=-5"]
                )
            case .cancelled:
                return (
                    .init(reason: .cancelled),
                    ["Network cancelled error", "Operation cancelled", "reason=cancelled"]
                )
            case .timeout:
                return (
                    .init(reason: .timeout, message: "Operation timed out", metadata: ["timeoutSeconds": "3.0"]),
                    ["Network timeout error", "Operation timed out", "reason=timeout", "timeoutSeconds=3.0"]
                )
            case .protocolViolation:
                return (
                    .init(
                        reason: .protocolViolation,
                        message: "Invalid protocol negotiation range",
                        metadata: ["minimumVersion": "1.4", "maximumVersion": "1.5"]
                    ),
                    [
                        "Network protocol error",
                        "Invalid protocol negotiation range",
                        "reason=protocol_violation",
                        "minimumVersion=1.4",
                        "maximumVersion=1.5"
                    ]
                )
            case .encoding:
                return (
                    .init(reason: .encoding, message: "Cannot encode request"),
                    ["Network encoding error", "Cannot encode request", "reason=encoding"]
                )
            case .decoding:
                return (
                    .init(reason: .decoding, message: "Cannot decode response"),
                    ["Network decoding error", "Cannot decode response", "reason=decoding"]
                )
            case .unknown:
                return (
                    .init(reason: .unknown),
                    ["Network unknown error", "Unknown network error", "reason=unknown"]
                )
            case .blankMessage:
                return (
                    .init(reason: .transport, message: " \n\t "),
                    ["Network transport error", "No additional message", "reason=transport"]
                )
            }
        }
    }

    struct NetworkDisplaySubstringCase: Sendable {
        let displayCase: NetworkDisplayCase
        let expectedSubstring: String
    }

    enum NetworkReasonClassificationCase: CaseIterable, Sendable {
        case transport
        case network
        case server
        case cancelled
        case timeout
        case protocolViolation
        case encoding
        case decoding
        case unknown

        var error: OpalBase.Network.Error {
            switch self {
            case .transport:
                return .init(reason: .transport)
            case .network:
                return .init(reason: .network)
            case .server:
                return .init(reason: .server(code: -5))
            case .cancelled:
                return .init(reason: .cancelled)
            case .timeout:
                return .init(reason: .timeout)
            case .protocolViolation:
                return .init(reason: .protocolViolation)
            case .encoding:
                return .init(reason: .encoding)
            case .decoding:
                return .init(reason: .decoding)
            case .unknown:
                return .init(reason: .unknown)
            }
        }

        var expectedCode: OpalDiagnostics.ErrorCode {
            switch self {
            case .transport,
                 .network:
                return .networkTransport
            case .server:
                return .networkServer
            case .cancelled:
                return .cancelled
            case .timeout:
                return .networkTimeout
            case .protocolViolation:
                return .networkProtocolViolation
            case .encoding:
                return .networkEncoding
            case .decoding:
                return .networkDecoding
            case .unknown:
                return .unknown
            }
        }
    }

    enum AllowlistedMetadataVisibilityCase: CaseIterable, Sendable {
        case invalidCloseCode
        case signedCloseCode
        case canonicalCloseCodeWithWhitespace
        case invalidTimeout
        case signedTimeout
        case canonicalNegativeZeroTimeout
        case invalidMinimumVersion
        case canonicalMaximumVersion

        var diagnosticMetadataExpectation: (
            key: String,
            value: String,
            publicFieldName: String,
            publicValue: String?,
            privateMetadataValues: Set<String>
        ) {
            switch self {
            case .invalidCloseCode:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.closeCode,
                    "9999",
                    OpalDiagnostics.Field.Name.closeCode,
                    nil,
                    ["closeCode=9999"]
                )
            case .signedCloseCode:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.closeCode,
                    "+1001",
                    OpalDiagnostics.Field.Name.closeCode,
                    nil,
                    ["closeCode=+1001"]
                )
            case .canonicalCloseCodeWithWhitespace:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.closeCode,
                    " 1001 ",
                    OpalDiagnostics.Field.Name.closeCode,
                    "1001",
                    []
                )
            case .invalidTimeout:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.timeoutSeconds,
                    "-1",
                    OpalDiagnostics.Field.Name.timeoutSeconds,
                    nil,
                    ["timeoutSeconds=-1"]
                )
            case .signedTimeout:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.timeoutSeconds,
                    "+3",
                    OpalDiagnostics.Field.Name.timeoutSeconds,
                    nil,
                    ["timeoutSeconds=+3"]
                )
            case .canonicalNegativeZeroTimeout:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.timeoutSeconds,
                    "-0.0",
                    OpalDiagnostics.Field.Name.timeoutSeconds,
                    "0.0",
                    []
                )
            case .invalidMinimumVersion:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.minimumVersion,
                    "1",
                    OpalDiagnostics.Field.Name.minimumVersion,
                    nil,
                    ["minimumVersion=1"]
                )
            case .canonicalMaximumVersion:
                return (
                    OpalBase.Network.Error.DiagnosticMetadataKey.maximumVersion,
                    "1.5",
                    OpalDiagnostics.Field.Name.maximumVersion,
                    "1.5",
                    []
                )
            }
        }
    }

    enum GenericLocalizedMessageCase: CaseIterable, Sendable {
        case blank
        case multiline

        var error: Swift.Error {
            switch self {
            case .blank:
                return LocalizedDescriptionError(description: " \n\t ")
            case .multiline:
                return LocalizedDescriptionError(description: "First line\nsecond\tline")
            }
        }

        var expectedMessage: String {
            switch self {
            case .blank:
                return "LocalizedDescriptionError(description: \" \\n\\t \")"
            case .multiline:
                return "First line second line"
            }
        }
    }

    enum FulcrumTranslationCase: CaseIterable, Sendable {
        case connectionClosed
        case reconnectFailed
        case heartbeatTimeout
        case cancellation
        case unknownCancellation
        case wrappedNetworkCancellation
        case decoding
        case encoding
        case unknownEncoding
        case normalizedDecodeMessage
        case contextualMempoolMinimumFeeDecodeMessage
        case contextualUnsupportedHashFunctionDecodeMessage

        var translationExpectation: (input: Swift.Error, expected: OpalBase.Network.Error) {
            switch self {
            case .connectionClosed:
                return (
                    SwiftFulcrum.Client.Error.transport(.connectionClosed(.goingAway, "wake reconnect")),
                    .init(
                        reason: .transport,
                        message: "wake reconnect",
                        metadata: ["closeCode": String(URLSessionWebSocketTask.CloseCode.goingAway.rawValue)]
                    )
                )
            case .reconnectFailed:
                return (
                    SwiftFulcrum.Client.Error.transport(.reconnectFailed),
                    .init(reason: .transport, message: "Reconnection attempts exhausted")
                )
            case .heartbeatTimeout:
                return (
                    SwiftFulcrum.Client.Error.transport(.heartbeatTimeout),
                    .init(reason: .timeout, message: "Heartbeat timed out")
                )
            case .cancellation:
                return (
                    CancellationError(),
                    .init(reason: .cancelled, message: "Operation cancelled")
                )
            case .unknownCancellation:
                return (
                    SwiftFulcrum.Client.Error.client(.unknown(CancellationError())),
                    .init(reason: .cancelled, message: "Operation cancelled")
                )
            case .wrappedNetworkCancellation:
                return (
                    DiagnosticsErrorPresentationValidator.wrappedNetworkCancellationError,
                    .init(reason: .cancelled)
                )
            case .decoding:
                return (
                    DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad payload")),
                    .init(
                        reason: .decoding,
                        message: String(describing: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad payload")))
                    )
                )
            case .encoding:
                return (
                    EncodingError.invalidValue("payload", .init(codingPath: [], debugDescription: "Bad request")),
                    .init(
                        reason: .encoding,
                        message: String(describing: EncodingError.invalidValue("payload", .init(codingPath: [], debugDescription: "Bad request")))
                    )
                )
            case .unknownEncoding:
                return (
                    SwiftFulcrum.Client.Error.client(.unknown(EncodingError.invalidValue("payload", .init(codingPath: [], debugDescription: "Bad request")))),
                    .init(
                        reason: .encoding,
                        message: String(describing: EncodingError.invalidValue("payload", .init(codingPath: [], debugDescription: "Bad request")))
                    )
                )
            case .normalizedDecodeMessage:
                return (
                    DescribedError(description: #"unexpectedFormat("Invalid mempoolminfee: -1")"#),
                    .init(reason: .decoding, message: "Invalid mempool minimum fee: -1")
                )
            case .contextualMempoolMinimumFeeDecodeMessage:
                return (
                    SwiftFulcrum.Client.Error.coding(.decode(DescribedError(description: #"unexpectedFormat("[payload: 128 B] Invalid mempoolminfee: -1")"#))),
                    .init(reason: .decoding, message: "Invalid mempool minimum fee: -1")
                )
            case .contextualUnsupportedHashFunctionDecodeMessage:
                return (
                    SwiftFulcrum.Client.Error.coding(.decode(DescribedError(description: #"unexpectedFormat("[method: server.features] [payload: 128 B] Unsupported server.features hash_function: sha1")"#))),
                    .init(reason: .protocolViolation, message: "Unsupported server feature hash function: sha1")
                )
            }
        }
    }

    enum FulcrumClassificationCase: CaseIterable, Sendable {
        case connectionClosed
        case reconnectFailed
        case heartbeatTimeout
        case encoding
        case decoding
        case cancelled
        case unknownCancellation
        case timeout
        case duplicateHandler
        case emptyResponse
        case invalidURL

        var error: SwiftFulcrum.Client.Error {
            switch self {
            case .connectionClosed:
                return .transport(.connectionClosed(.goingAway, nil))
            case .reconnectFailed:
                return .transport(.reconnectFailed)
            case .heartbeatTimeout:
                return .transport(.heartbeatTimeout)
            case .encoding:
                return .coding(.encode(nil))
            case .decoding:
                return .coding(.decode(nil))
            case .cancelled:
                return .client(.cancelled)
            case .unknownCancellation:
                return .client(.unknown(CancellationError()))
            case .timeout:
                return .client(.timeout(.seconds(3)))
            case .duplicateHandler:
                return .client(.duplicateHandler)
            case .emptyResponse:
                return .client(.emptyResponse(nil))
            case .invalidURL:
                return .client(.invalidURL("wss://private.example"))
            }
        }

        var expectedCode: OpalDiagnostics.ErrorCode {
            switch self {
            case .connectionClosed,
                 .reconnectFailed,
                 .duplicateHandler,
                 .invalidURL:
                return .networkTransport
            case .heartbeatTimeout,
                 .timeout:
                return .networkTimeout
            case .encoding:
                return .networkEncoding
            case .decoding:
                return .networkDecoding
            case .cancelled:
                return .cancelled
            case .unknownCancellation:
                return .cancelled
            case .emptyResponse:
                return .networkProtocolViolation
            }
        }
    }

    enum CancellationRecognitionCase: CaseIterable, Sendable {
        case cancellation
        case reflectedCancellation
        case urlCancellation
        case networkCancellation
        case fulcrumCancellation
        case wrappedFulcrumCancellation
        case wrappedNetworkCancellation
        case timeout

        var error: Swift.Error {
            switch self {
            case .cancellation:
                return CancellationError()
            case .reflectedCancellation:
                return NSError(domain: String(reflecting: CancellationError.self), code: 1)
            case .urlCancellation:
                return NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            case .networkCancellation:
                return OpalBase.Network.Error(reason: .cancelled)
            case .fulcrumCancellation:
                return SwiftFulcrum.Client.Error.client(.cancelled)
            case .wrappedFulcrumCancellation:
                return SwiftFulcrum.Client.Error.client(.unknown(CancellationError()))
            case .wrappedNetworkCancellation:
                return DiagnosticsErrorPresentationValidator.wrappedNetworkCancellationError
            case .timeout:
                return OpalBase.Network.Error(reason: .timeout)
            }
        }

        var expectedResult: Bool {
            switch self {
            case .cancellation,
                 .reflectedCancellation,
                 .urlCancellation,
                 .networkCancellation,
                 .fulcrumCancellation,
                 .wrappedFulcrumCancellation,
                 .wrappedNetworkCancellation:
                return true
            case .timeout:
                return false
            }
        }
    }

    enum OpalBaseErrorDomainClassificationCase: CaseIterable, Sendable {
        case wallet
        case account
        case accountInvalidExtendedPublicKey
        case accountExtendedPublicKeyMismatch
        case accountPrivateKeyMaterialUnavailable
        case accountFeePreference
        case accountTokenSelection
        case network
        case storage
        case storageSecurity
        case transaction
        case claimable
        case cashTokens
        case bcmrClient
        case bcmrFetcher
        case hedge
        case publicKey
        case derivationPath
        case mnemonic
        case mnemonicAccountExtendedPublicKey
        case encoding

        var diagnosticsClassificationExpectation: (error: Swift.Error, expectedCode: OpalDiagnostics.ErrorCode) {
            switch self {
            case .wallet:
                return (OpalBase.Wallet.Error.accountAlreadyExists(index: 0), .walletAccountAlreadyExists)
            case .account:
                return (OpalBase.Account.Error.paymentHasNoRecipients, .accountPaymentInvalid)
            case .accountInvalidExtendedPublicKey:
                return (OpalBase.Account.Error.invalidAccountExtendedPublicKey, .keyInvalid)
            case .accountExtendedPublicKeyMismatch:
                return (OpalBase.Account.Error.accountExtendedPublicKeyDoesNotMatchAccount, .keyInvalid)
            case .accountPrivateKeyMaterialUnavailable:
                return (OpalBase.Account.Error.privateKeyMaterialUnavailable, .accountTransactionBuildFailed)
            case .accountFeePreference:
                return (
                    OpalBase.Account.Error.feePreferenceUnavailable(NetworkStubError.forced("fee")),
                    .accountTransactionBuildFailed
                )
            case .accountTokenSelection:
                return (
                    OpalBase.Account.Error.tokenSelectionFailed(NetworkStubError.forced("selection")),
                    .accountCoinSelectionFailed
                )
            case .network:
                return (OpalBase.Network.Error(reason: .timeout), .networkTimeout)
            case .storage:
                return (OpalBase.Storage.Error.persistenceUnavailable, .storagePersistenceFailed)
            case .storageSecurity:
                return (OpalBase.Storage.Security.Error.protectionUnavailable, .storagePersistenceFailed)
            case .transaction:
                return (OpalBase.Transaction.Error.insufficientFunds(required: 1), .transactionInsufficientFunds)
            case .claimable:
                return (OpalBase.Claimable.Error.invalidEnvelopeLength(expected: 1, actual: 2), .claimableInvalidEnvelope)
            case .cashTokens:
                return (OpalBase.CashTokens.Error.invalidTokenPrefix, .cashTokensInvalid)
            case .bcmrClient:
                return (
                    OpalBase.CashTokens.BCMR.Client.Error.registryDecodingFailed(NetworkStubError.forced("registry")),
                    .cashTokensBCMRFailed
                )
            case .bcmrFetcher:
                return (OpalBase.CashTokens.BCMR.Client.Fetcher.Error.unsupportedScheme("ftp"), .cashTokensBCMRFetchFailed)
            case .hedge:
                return (OpalBase.Hedge.Error.invalidFundingAmount(-1), .hedgeInvalid)
            case .publicKey:
                return (OpalBase.Key.PublicKey.Error.invalidFormat, .keyInvalid)
            case .derivationPath:
                return (OpalBase.Key.DerivationPath.Error.indexOverflow, .keyInvalid)
            case .mnemonic:
                return (OpalBase.Key.Mnemonic.Error.invalidWordCount(actual: 11), .keyInvalid)
            case .mnemonicAccountExtendedPublicKey:
                return (OpalBase.Key.Mnemonic.Error.accountExtendedPublicKeyDerivationFailed, .keyInvalid)
            case .encoding:
                return (OpalBase.Encoding.Error.invalidHexadecimalString, .encodingInvalid)
            }
        }
    }
}
