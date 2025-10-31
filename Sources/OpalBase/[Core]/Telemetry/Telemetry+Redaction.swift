// Telemetry+Redaction.swift

import Foundation

struct TelemetryRedactor: Sendable {
    enum Constants {
        static let redactedToken = "‹redacted›"
    }
    
    func sanitise(event: Telemetry.Event) -> Telemetry.Event {
        var sanitised = event
        if let message = event.message {
            sanitised.message = sanitise(message: message)
        }
        sanitised.metadata = sanitise(metadata: event.metadata, sensitiveKeys: event.sensitiveKeys)
        return sanitised
    }
    
    private func sanitise(message: String) -> String {
        let segments = message.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !segments.isEmpty else { return message }
        return segments.map { token -> String in
            guard let trimmed = trimSensitivePortion(in: token) else { return token }
            return token.replacingOccurrences(of: trimmed, with: Constants.redactedToken)
        }.joined(separator: " ")
    }
    
    private func sanitise(
        metadata: Telemetry.Metadata,
        sensitiveKeys: Set<Telemetry.Metadata.Key>
    ) -> Telemetry.Metadata {
        var sanitised = metadata
        for key in metadata.keys {
            if sensitiveKeys.contains(key) {
                sanitised[key] = .redacted
                continue
            }
            if case .string(let value)? = metadata[key], shouldRedact(token: value) {
                sanitised[key] = .redacted
            }
        }
        return sanitised
    }
    
    private func trimSensitivePortion(in token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !trimmed.isEmpty else { return nil }
        guard shouldRedact(token: trimmed) else { return nil }
        return trimmed
    }
    
    private func shouldRedact(token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.count >= 8 && trimmed.isLikelyHexadecimal { return true }
        var digitCount = 0
        for character in trimmed where character.isNumber {
            digitCount += 1
        }
        if digitCount >= 6 { return true }
        if trimmed.contains(where: { !$0.isAlphaNumeric }) && trimmed.count >= 12 { return true }
        return false
    }
}

private extension String {
    var isLikelyHexadecimal: Bool {
        guard !isEmpty else { return false }
        return allSatisfy { $0.isHexDigit }
    }
}

private extension Character {
    var isAlphaNumeric: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
    
    var isHexDigit: Bool {
        unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }
}
