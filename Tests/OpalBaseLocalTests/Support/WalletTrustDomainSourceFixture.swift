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

    static func readPublicInteractorSources() throws -> String {
        try [
            "Sources/OpalBase/Public/OpalBase+WalletAccountPublicDescriptor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletPublicChainOperations.swift",
            "Sources/OpalBase/Public/OpalBase+WalletSnapshotInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletBlockchainSyncInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletTransportInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletReceiveAddressInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletSecretAccessInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletTransactionAuthoringInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletBroadcastInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletManagementInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletAssetInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+ClaimableInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+WalletObservabilityInteractor.swift",
            "Sources/OpalBase/Public/OpalBase+CashFusionInteractor.swift"
        ]
        .map(readSource)
        .joined(separator: "\n")
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
