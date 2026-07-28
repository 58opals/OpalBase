// URLHostValidation+FetchPolicy.swift

import Darwin

extension URLHostValidation {
    /// Returns whether host syntax avoids private or reserved IP literals and local-use names.
    ///
    /// This check intentionally does not resolve domain names and cannot prevent DNS rebinding.
    static func isAllowedFetchHostSyntax(_ host: String) -> Bool {
        var normalizedHost = host.lowercased()
        while normalizedHost.last == "." {
            normalizedHost.removeLast()
        }
        guard !normalizedHost.isEmpty else { return false }

        if let addressBytes = makeInternetProtocolVersion4AddressBytes(normalizedHost) {
            return isPublicInternetProtocolVersion4Address(addressBytes)
        }
        if isLegacyInternetProtocolVersion4Literal(normalizedHost) {
            return false
        }
        if let addressBytes = makeInternetProtocolVersion6AddressBytes(normalizedHost) {
            return isPublicInternetProtocolVersion6Address(addressBytes)
        }

        guard isValidDomainName(normalizedHost) else { return false }
        let labels = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1 else { return false }

        let localSuffixes = [
            "localhost",
            "local",
            "localdomain",
            "lan",
            "home.arpa",
            "internal",
            "intranet",
            "corp"
        ]
        return !localSuffixes.contains { suffix in
            normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
        }
    }

    private static func makeInternetProtocolVersion4AddressBytes(_ literal: String) -> [UInt8]? {
        var address = in_addr()
        guard literal.withCString({ inet_pton(AF_INET, $0, &address) == 1 }) else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func makeInternetProtocolVersion6AddressBytes(_ literal: String) -> [UInt8]? {
        var address = in6_addr()
        guard literal.withCString({ inet_pton(AF_INET6, $0, &address) == 1 }) else {
            return nil
        }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func isLegacyInternetProtocolVersion4Literal(_ literal: String) -> Bool {
        var address = in_addr()
        return literal.withCString { inet_aton($0, &address) == 1 }
    }

    private static func isPublicInternetProtocolVersion4Address(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }

        if bytes[0] == 192,
           bytes[1] == 0,
           bytes[2] == 0,
           (9...10).contains(bytes[3]) {
            return true
        }

        switch (bytes[0], bytes[1], bytes[2]) {
        case (0, _, _),
             (10, _, _),
             (100, 64...127, _),
             (127, _, _),
             (169, 254, _),
             (172, 16...31, _),
             (192, 0, 0),
             (192, 0, 2),
             (192, 88, 99),
             (192, 168, _),
             (198, 18...19, _),
             (198, 51, 100),
             (203, 0, 113),
             (224...255, _, _):
            return false
        default:
            return true
        }
    }

    private static func isPublicInternetProtocolVersion6Address(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16,
              bytes[0] & 0xe0 == 0x20 else {
            return false
        }

        if bytes[0] == 0x20,
           bytes[1] == 0x01,
           bytes[2] <= 0x01 {
            return false
        }
        if bytes[0] == 0x20,
           bytes[1] == 0x01,
           bytes[2] == 0x0d,
           bytes[3] == 0xb8 {
            return false
        }
        if bytes[0] == 0x20,
           bytes[1] == 0x02 {
            return false
        }
        if bytes[0] == 0x3f,
           bytes[1] == 0xfe {
            return false
        }
        if bytes[0] == 0x3f,
           bytes[1] == 0xff,
           bytes[2] & 0xf0 == 0 {
            return false
        }

        return true
    }
}
