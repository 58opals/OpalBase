// URLHostValidation.swift

import Darwin

enum URLHostValidation {
    static func isValidInternetProtocolLiteral(_ literal: String) -> Bool {
        isValidInternetProtocolVersion4Literal(literal)
            || isValidInternetProtocolVersion6Literal(literal)
    }

    static func isValidBracketedInternetProtocolLiteral(_ host: String) -> Bool {
        guard host.first == "[", host.last == "]" else {
            return false
        }
        return isValidInternetProtocolVersion6Literal(String(host.dropFirst().dropLast()))
    }

    static func isValidUnbracketedHostLiteralOrName(_ host: String) -> Bool {
        if host.contains(":") {
            return isValidInternetProtocolLiteral(host)
        }
        return !isMalformedInternetProtocolVersion4LiteralHost(host)
    }

    static func isMalformedInternetProtocolVersion4LiteralHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let trailingEmptyLabelCount = labels.reversed().prefix { $0.isEmpty }.count
        let addressLabels = labels.dropLast(trailingEmptyLabelCount)
        guard addressLabels.count == 4,
              addressLabels.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (0x30...0x39).contains($0) } }) else {
            return false
        }
        guard trailingEmptyLabelCount <= 1 else { return true }
        return !isValidInternetProtocolVersion4Literal(addressLabels.joined(separator: "."))
    }

    private static func isValidInternetProtocolVersion4Literal(_ literal: String) -> Bool {
        var address = in_addr()
        return literal.withCString { inet_pton(AF_INET, $0, &address) == 1 }
    }

    private static func isValidInternetProtocolVersion6Literal(_ literal: String) -> Bool {
        var address = in6_addr()
        return literal.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
    }
}
