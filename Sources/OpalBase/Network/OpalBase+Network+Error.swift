// OpalBase+Network+Error.swift

import Foundation

extension _OpalBase.Network {
    public struct Error: Swift.Error, Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            case transport
            case network
            case server(code: Int)
            case cancelled
            case timeout
            case protocolViolation
            case encoding
            case decoding
            case unknown
        }
        
        public let reason: Reason
        public let message: String?
        public let metadata: [String: String]
        
        public init(reason: Reason, message: String? = nil, metadata: [String: String] = .init()) {
            self.reason = reason
            self.message = message
            self.metadata = metadata
        }

        enum DiagnosticMetadataKey {
            static let closeCode = "closeCode"
            static let timeoutSeconds = "timeoutSeconds"
            static let minimumVersion = "minimumVersion"
            static let maximumVersion = "maximumVersion"
            static let serverIdentifier = "serverIdentifier"
            static let serverURL = "serverURL"
            static let requestIdentifier = "requestIdentifier"

            static let publicDiagnosticKeys = [
                closeCode,
                timeoutSeconds,
                minimumVersion,
                maximumVersion
            ]
        }
    }
}

extension _OpalBase.Network.Error: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
    public var errorDescription: String? {
        description
    }

    public var description: String {
        var text = "Network \(reason.displayName) error: \(message.map(Self.sanitizeMessage) ?? reason.defaultMessage)"
        text += " (" + displayMetadata.map { "\($0.name)=\($0.value)" }.joined(separator: ", ") + ")"

        return text
    }

    public var debugDescription: String {
        description
    }
}

extension _OpalBase.Network.Error.Reason: CustomStringConvertible {
    public var description: String {
        diagnosticName
    }
}

extension _OpalBase.Network.Error {
    var publicDiagnosticMetadata: [(name: String, value: String)] {
        Self.DiagnosticMetadataKey.publicDiagnosticKeys.compactMap { key in
            metadata[key].flatMap { value in
                Self.makePublicDiagnosticMetadataValue(for: key, value: value).map {
                    (name: key, value: $0)
                }
            }
        }
    }

    var privateDiagnosticMetadata: [(name: String, value: String)] {
        let publicMetadata = Set(publicDiagnosticMetadata.map(\.name))
        return metadata
            .filter { !publicMetadata.contains($0.key) }
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private var displayMetadata: [(name: String, value: String)] {
        var result = [(name: "reason", value: reason.diagnosticName)]

        if case .server(let code) = reason {
            result.append((name: "serverCode", value: String(code)))
        }

        result += publicDiagnosticMetadata

        return result
    }

    private static func makePublicDiagnosticMetadataValue(for key: String, value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch key {
        case DiagnosticMetadataKey.closeCode:
            return makePublicCloseCode(trimmedValue)
        case DiagnosticMetadataKey.timeoutSeconds:
            return makePublicTimeoutSeconds(trimmedValue)
        case DiagnosticMetadataKey.minimumVersion, DiagnosticMetadataKey.maximumVersion:
            return makePublicProtocolVersion(trimmedValue)
        default:
            return nil
        }
    }

    private static func makePublicCloseCode(_ value: String) -> String? {
        guard !hasExplicitPositiveSign(value),
              let closeCode = UInt16(value),
              (1000...4999).contains(closeCode)
        else { return nil }
        return String(closeCode)
    }

    private static func makePublicTimeoutSeconds(_ value: String) -> String? {
        guard !hasExplicitPositiveSign(value),
              let seconds = Double(value),
              seconds.isFinite,
              seconds >= 0
        else { return nil }
        return String(seconds == 0 ? 0 : seconds)
    }

    private static func hasExplicitPositiveSign(_ value: String) -> Bool {
        value.first == "+"
    }

    private static func makePublicProtocolVersion(_ value: String) -> String? {
        OpalBase.Network.ProtocolVersion(string: value)?.description
    }

    private static let sensitiveMessageRedactions: [(pattern: String, replacement: String)] = [
        (#"\b[a-z][a-z0-9+.-]*://[^\s,;)]+(?:\)[^\s,;)]*)?"#, "[redacted-url]"),
        (#"\[[0-9a-fA-F:]+\]:\d{1,5}\b"#, "[redacted-endpoint]"),
        (#"\b(?:(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}|localhost|(?:\d{1,3}\.){3}\d{1,3}):\d{1,5}\b"#, "[redacted-endpoint]"),
        (#"\b(?:bitcoincash|bchtest|bchreg):[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{20,}\b"#, "[redacted-address]"),
        (#"\b[qpz][qpzry9x8gf2tvdw0s3jn54khce6mua7l]{41,}\b"#, "[redacted-address]"),
        (#"\b[13][1-9A-HJ-NP-Za-km-z]{25,34}\b"#, "[redacted-address]"),
        (#"\b(?:[5KL][1-9A-HJ-NP-Za-km-z]{50,51}|[9c][1-9A-HJ-NP-Za-km-z]{50,51})\b"#, "[redacted-private-key]"),
        (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#, "[redacted-identifier]"),
        (#"\b[0-9a-fA-F]{64,}\b"#, "[redacted-identifier]")
    ]

    private static func sanitizeMessage(_ message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return "No additional message" }
        let singleLineMessage = trimmedMessage.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return sensitiveMessageRedactions.reduce(singleLineMessage) { sanitized, redaction in
            sanitized.replacingOccurrences(
                of: redaction.pattern,
                with: redaction.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }
}

private extension _OpalBase.Network.Error.Reason {
    var diagnosticName: String {
        switch self {
        case .transport:
            return "transport"
        case .network:
            return "network"
        case .server:
            return "server"
        case .cancelled:
            return "cancelled"
        case .timeout:
            return "timeout"
        case .protocolViolation:
            return "protocol_violation"
        case .encoding:
            return "encoding"
        case .decoding:
            return "decoding"
        case .unknown:
            return "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .transport:
            return "transport"
        case .network:
            return "connection"
        case .server:
            return "server"
        case .cancelled:
            return "cancelled"
        case .timeout:
            return "timeout"
        case .protocolViolation:
            return "protocol"
        case .encoding:
            return "encoding"
        case .decoding:
            return "decoding"
        case .unknown:
            return "unknown"
        }
    }

    var defaultMessage: String {
        switch self {
        case .transport:
            return "Transport failure"
        case .network:
            return "Network connection failure"
        case .server:
            return "Server returned an error"
        case .cancelled:
            return "Operation cancelled"
        case .timeout:
            return "Operation timed out"
        case .protocolViolation:
            return "Protocol violation"
        case .encoding:
            return "Encoding failed"
        case .decoding:
            return "Decoding failed"
        case .unknown:
            return "Unknown network error"
        }
    }
}
