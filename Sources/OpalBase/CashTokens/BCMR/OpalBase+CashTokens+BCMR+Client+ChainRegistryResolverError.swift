// OpalBase+CashTokens+BCMR+Client+ChainRegistryResolverError.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public enum ChainRegistryResolverError: Swift.Error, Sendable {
        case missingPublicationOutput(OpalBase.Transaction.Hash)
        case invalidRegistryHash(expected: Data, actual: Data)
        case registryDecodingFailed(Swift.Error)
        case registryFetchingFailed(String, Swift.Error)
        case noRegistryLocation(OpalBase.Transaction.Hash)
    }
}
