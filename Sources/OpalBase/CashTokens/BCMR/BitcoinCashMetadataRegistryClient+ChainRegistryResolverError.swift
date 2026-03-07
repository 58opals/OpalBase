// BitcoinCashMetadataRegistryClient+ChainRegistryResolverError.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
    public enum ChainRegistryResolverError: Swift.Error, Sendable {
        case missingPublicationOutput(OpalBase.Transaction.HashModel)
        case invalidRegistryHash(expected: Data, actual: Data)
        case registryDecodingFailed(Swift.Error)
        case registryFetchingFailed(String, Swift.Error)
        case noRegistryLocation(OpalBase.Transaction.HashModel)
    }
}
