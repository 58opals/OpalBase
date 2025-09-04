// OpalBase.swift

import Foundation

public enum OpalBase {
    public static let version = "0.2.0"
}

extension OpalBase {
    public enum Error: Swift.Error {
        case mnemonicFailure(Swift.Error)
        case missingStorageLocation
    }
}

extension OpalBase {
    public static func bootstrap(storage: StorageConfiguration,
                                 network: NetworkPolicy) async throws -> WalletCore {
        if !storage.isMemoryOnly && storage.appGroupContainer == nil {
            throw Error.missingStorageLocation
        }
        
        let config: Storage.Configuration = storage.isMemoryOnly ? .memory : .disk(appGroup: nil)
        let facade = try Storage.Facade(configuration: config)
        
        let chain = StubChainClient()
        let gateway = Network.TransactionGateway(client: StubGatewayClient())
        let core = WalletCore(chainClient: chain, storage: facade, transactionGateway: gateway)
        try await core.sync()
        return core
    }
}

private struct StubChainClient: ChainClient {
    func connect() async throws {}
    func disconnect() {}
}

private struct StubGatewayClient: Network.TransactionGateway.Client {
    func currentMempool() async throws -> Set<Transaction.Hash> { [] }
    func broadcast(_ transaction: Transaction) async throws {}
    func fetch(_ hash: Transaction.Hash) async throws -> Transaction? { nil }
}
