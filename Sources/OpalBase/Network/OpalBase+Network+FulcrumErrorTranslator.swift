// OpalBase+Network+FulcrumErrorTranslator.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    static func performWithFailureTranslation<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            throw FulcrumErrorTranslator.translate(error)
        }
    }

    static func areFailuresEquivalent(_ left: Swift.Error, _ right: Swift.Error) -> Bool {
        FulcrumErrorTranslator.areFailuresEquivalent(left, right)
    }

    enum FulcrumErrorTranslator {
        private static func describe(_ error: Swift.Error?) -> String? {
            guard let error else { return nil }
            return String(describing: error)
        }

        static func translate(_ error: Swift.Error) -> OpalBase.Network.Error {
            if let failure = error as? OpalBase.Network.Error { return failure }

            if let dataError = error as? Data.Error {
                return OpalBase.Network.Error(reason: .decoding, message: describe(dataError))
            }

            if let codingFailure = translateFoundationCodingError(error) {
                return codingFailure
            }

            if let decodeFailure = translateSwiftFulcrumResultDecodeMessage(String(describing: error)) {
                return OpalBase.Network.Error(reason: decodeFailure.reason, message: decodeFailure.message)
            }

            if error is CancellationError {
                return OpalBase.Network.Error(reason: .cancelled, message: "Operation cancelled")
            }

            guard let fulcrumError = error as? SwiftFulcrum.Client.Error else {
                return OpalBase.Network.Error(reason: .unknown, message: String(describing: error))
            }

            switch fulcrumError {
            case .transport(let transport):
                return translateTransport(transport)
            case .rpc(let server):
                return OpalBase.Network.Error(
                    reason: .server(code: server.code),
                    message: server.message,
                    metadata: [OpalBase.Network.Error.DiagnosticMetadataKey.serverIdentifier: server.id?.uuidString ?? "unknown"]
                )
            case .coding(let coding):
                return translateCoding(coding)
            case .client(let clientError):
                return translateClient(clientError)
            }
        }

        static func areFailuresEquivalent(_ left: Swift.Error, _ right: Swift.Error) -> Bool {
            let leftFailure = translate(left)
            let rightFailure = translate(right)
            return leftFailure.reason == rightFailure.reason &&
                leftFailure.message == rightFailure.message &&
                stableMetadata(from: leftFailure.metadata) == stableMetadata(from: rightFailure.metadata)
        }

        static func isCancellation(_ error: Swift.Error) -> Bool {
            if error is CancellationError { return true }
            if let failure = error as? OpalBase.Network.Error { return failure.reason == .cancelled }
            if let fulcrumError = error as? SwiftFulcrum.Client.Error {
                switch fulcrumError {
                case .client(.cancelled):
                    return true
                case .client(.unknown(let underlying)):
                    return underlying?.isCancellationError == true
                default:
                    return false
                }
            }
            return false
        }

        private static func stableMetadata(from metadata: [String: String]) -> [String: String] {
            metadata.filter { key, _ in
                key != OpalBase.Network.Error.DiagnosticMetadataKey.serverIdentifier &&
                    key != OpalBase.Network.Error.DiagnosticMetadataKey.requestIdentifier
            }
        }

        private static func translateTransport(_ transport: SwiftFulcrum.Client.Error.Transport) -> OpalBase.Network.Error {
            switch transport {
            case .setupFailed:
                return OpalBase.Network.Error(reason: .transport, message: "Failed to create transport")
            case .connectionClosed(let code, let reason):
                return OpalBase.Network.Error(
                    reason: .transport,
                    message: reason ?? "Connection closed",
                    metadata: [OpalBase.Network.Error.DiagnosticMetadataKey.closeCode: String(code.rawValue)]
                )
            case .network(let networkError):
                return translateNetwork(networkError)
            case .reconnectFailed:
                return OpalBase.Network.Error(reason: .transport, message: "Reconnection attempts exhausted")
            case .heartbeatTimeout:
                return OpalBase.Network.Error(reason: .timeout, message: "Heartbeat timed out")
            }
        }

        private static func translateNetwork(_ network: SwiftFulcrum.Client.Error.Network) -> OpalBase.Network.Error {
            switch network {
            case .tlsNegotiationFailed(let underlying):
                return OpalBase.Network.Error(
                    reason: .network,
                    message: underlying?.localizedDescription ?? "TLS negotiation failed"
                )
            }
        }

        private static func translateCoding(_ coding: SwiftFulcrum.Client.Error.Coding) -> OpalBase.Network.Error {
            switch coding {
            case .encode(let underlying):
                return OpalBase.Network.Error(reason: .encoding, message: describe(underlying))
            case .decode(let underlying):
                guard let description = describe(underlying) else {
                    return OpalBase.Network.Error(reason: .decoding)
                }
                if let decodeFailure = translateSwiftFulcrumResultDecodeMessage(description) {
                    return OpalBase.Network.Error(reason: decodeFailure.reason, message: decodeFailure.message)
                }
                return OpalBase.Network.Error(reason: .decoding, message: description)
            }
        }

        private struct TranslatedDecodeFailure {
            let reason: OpalBase.Network.Error.Reason
            let message: String
        }

        private static func translateSwiftFulcrumResultDecodeMessage(_ description: String) -> TranslatedDecodeFailure? {
            let prefixes = [".unexpectedFormat(\"", "unexpectedFormat(\""]
            guard let prefix = prefixes.first(where: { description.hasPrefix($0) }),
                  description.hasSuffix("\")") else {
                return nil
            }

            let start = description.index(description.startIndex, offsetBy: prefix.count)
            let end = description.index(description.endIndex, offsetBy: -2)
            let message = String(description[start..<end])

            return translateSwiftFulcrumDecodeMessage(message)
        }

        private static func translateSwiftFulcrumDecodeMessage(_ message: String) -> TranslatedDecodeFailure {
            let payloadMessage = swiftFulcrumDecodePayloadMessage(from: message)

            if let hashFunction = value(in: payloadMessage, after: "Unsupported server.features hash_function: ") {
                return .init(
                    reason: .protocolViolation,
                    message: "Unsupported server feature hash function: \(hashFunction)"
                )
            }

            if let prefixRangeMessage = translateReusablePaymentAddressPrefixRangeMessage(payloadMessage) {
                return .init(reason: .decoding, message: prefixRangeMessage)
            }

            let mappings = [
                ("Invalid mempoolminfee: ", "Invalid mempool minimum fee: "),
                ("Invalid minrelaytxfee: ", "Invalid minimum relay transaction fee: "),
                ("Invalid incrementalrelayfee: ", "Invalid incremental relay fee: "),
                ("Invalid unbroadcastcount: ", "Invalid unbroadcast count: "),
                ("Invalid server.features pruning: ", "Invalid server feature pruning limit: "),
                ("Invalid server.features host ssl_port: ", "Invalid server feature ssl port: "),
                ("Invalid server.features host tcp_port: ", "Invalid server feature tcp port: "),
                ("Invalid server.features host ws_port: ", "Invalid server feature websocket port: "),
                ("Invalid server.features host wss_port: ", "Invalid server feature secure websocket port: "),
                ("Invalid server.features rpa history_block_limit: ", "Invalid server feature rpa history block limit: "),
                ("Invalid server.features rpa max_history: ", "Invalid server feature rpa maximum history items: "),
                ("Invalid server.features rpa prefix_bits: ", "Invalid server feature rpa indexed prefix bits: "),
                ("Invalid server.features rpa prefix_bits_min: ", "Invalid server feature rpa minimum prefix bits: "),
                ("Invalid server.features rpa starting_height: ", "Invalid server feature rpa starting height: ")
            ]

            for (wirePrefix, publicPrefix) in mappings {
                guard payloadMessage.hasPrefix(wirePrefix) else { continue }
                return .init(reason: .decoding, message: publicPrefix + payloadMessage.dropFirst(wirePrefix.count))
            }

            return .init(reason: .decoding, message: payloadMessage)
        }

        private static func swiftFulcrumDecodePayloadMessage(from message: String) -> String {
            var remaining = message[...]

            while remaining.hasPrefix("[") {
                guard let endIndex = remaining.firstIndex(of: "]") else { break }

                let label = remaining[remaining.index(after: remaining.startIndex)..<endIndex]
                guard label.hasPrefix("method:") || label.hasPrefix("payload:") else { break }

                remaining = remaining[remaining.index(after: endIndex)...]
                remaining = remaining.drop(while: { $0 == " " })
            }

            return String(remaining)
        }

        private static func translateReusablePaymentAddressPrefixRangeMessage(_ message: String) -> String? {
            guard let suffix = value(in: message, after: "Invalid server.features rpa prefix bit range: "),
                  let separatorRange = suffix.range(of: " exceeds ") else {
                return nil
            }

            let minimum = suffix[..<separatorRange.lowerBound]
            let indexed = suffix[separatorRange.upperBound...]
            return "Invalid server feature rpa prefix range: minimum \(minimum) exceeds indexed \(indexed)"
        }

        private static func value(in message: String, after prefix: String) -> String? {
            guard message.hasPrefix(prefix) else { return nil }
            return String(message.dropFirst(prefix.count))
        }

        private static func translateClient(_ client: SwiftFulcrum.Client.Error.ClientIssue) -> OpalBase.Network.Error {
            switch client {
            case .urlNotFound:
                return OpalBase.Network.Error(reason: .transport, message: "No server URL available")
            case .invalidURL(let string):
                return OpalBase.Network.Error(
                    reason: .transport,
                    message: "Invalid server URL",
                    metadata: [OpalBase.Network.Error.DiagnosticMetadataKey.serverURL: string]
                )
            case .duplicateHandler:
                return OpalBase.Network.Error(reason: .transport, message: "Duplicate handler registered")
            case .cancelled:
                return OpalBase.Network.Error(reason: .cancelled, message: "Operation cancelled")
            case .timeout(let duration):
                return OpalBase.Network.Error(
                    reason: .timeout,
                    message: "Operation timed out",
                    metadata: [OpalBase.Network.Error.DiagnosticMetadataKey.timeoutSeconds: String(duration.totalSeconds)]
                )
            case .emptyResponse(let identifier):
                return OpalBase.Network.Error(reason: .protocolViolation,
                                       message: "Empty response from server",
                                       metadata: identifier.map { [OpalBase.Network.Error.DiagnosticMetadataKey.requestIdentifier: $0.uuidString] } ?? .init())
            case .protocolMismatch(let message):
                return OpalBase.Network.Error(reason: .protocolViolation, message: message)
            case .invalidProtocolNegotiationRange(minimumVersion: let min, maximumVersion: let max):
                return OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Invalid protocol negotiation range",
                    metadata: [
                        OpalBase.Network.Error.DiagnosticMetadataKey.minimumVersion: min.description,
                        OpalBase.Network.Error.DiagnosticMetadataKey.maximumVersion: max.description
                    ]
                )
            case .unknown(let underlying):
                guard let underlying else {
                    return OpalBase.Network.Error(reason: .unknown, message: nil)
                }

                if let networkFailure = underlying as? OpalBase.Network.Error {
                    return networkFailure
                }

                if underlying.isCancellationError {
                    return OpalBase.Network.Error(reason: .cancelled, message: "Operation cancelled")
                }

                if let codingFailure = translateFoundationCodingError(underlying) {
                    return codingFailure
                }

                let cocoaError = underlying as NSError
                if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == 3840 {
                    return OpalBase.Network.Error(reason: .decoding, message: describe(underlying))
                }

                return OpalBase.Network.Error(reason: .unknown, message: describe(underlying))
            }
        }

        private static func translateFoundationCodingError(_ error: Swift.Error) -> OpalBase.Network.Error? {
            if let decodingError = error as? DecodingError {
                return OpalBase.Network.Error(reason: .decoding, message: String(describing: decodingError))
            }

            if let encodingError = error as? EncodingError {
                return OpalBase.Network.Error(reason: .encoding, message: String(describing: encodingError))
            }

            return nil
        }
    }
}

extension Swift.Error {
    var isCancellationError: Bool {
        OpalBase.Network.FulcrumErrorTranslator.isCancellation(self)
    }
}
