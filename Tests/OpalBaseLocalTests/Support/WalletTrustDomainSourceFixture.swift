// WalletTrustDomainSourceFixture.swift

import Foundation

enum WalletTrustDomainSourceFixture {
    static func readSourcePrefix(
        _ relativePath: String,
        before marker: String
    ) throws -> String {
        let source = try readSource(relativePath)
        guard let markerRange = source.range(of: marker) else {
            return source
        }
        return String(source[..<markerRange.lowerBound])
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let fileURL = packageRootURL()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
