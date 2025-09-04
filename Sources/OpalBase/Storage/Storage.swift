// Storage.swift

import Foundation

public enum Storage {}

extension Storage {
    public enum Error: Swift.Error, Sendable {
        case platformUnavailable
        case persistenceFailure(Swift.Error)
        case keychainError(OSStatus)
    }
}

#if canImport(SwiftData)
import SwiftData

extension Storage {
    public enum Configuration: Sendable {
        case disk(appGroup: String? = nil, filename: String = "opal.sqlite")
        case memory

        var isMemoryOnly: Bool {
            if case .memory = self { return true }
            return false
        }

        func makeContainer() throws -> ModelContainer {
            let schema = Schema([
                Entity.Header.self,
                Entity.UTXO.self,
                Entity.Transaction.self,
                Entity.Account.self,
                Entity.Fee.self,
                Entity.ServerHealth.self,
                Entity.Subscription.self
            ])

            switch self {
            case .memory:
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: config)
            case .disk(let appGroup, let filename):
                let baseURL: URL = {
                    if let group = appGroup,
                       let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                        return url
                    } else {
                        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    }
                }()
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
                let url = baseURL.appendingPathComponent(filename, isDirectory: false)
                let config = ModelConfiguration(url: url)
                return try ModelContainer(for: schema, configurations: config)
            }
        }
    }
}

extension Storage {
    public actor Facade {
        public let container: ModelContainer

        public let headers: Repository.Headers
        public let utxos: Repository.UTXOs
        public let transactions: Repository.Transactions
        public let accounts: Repository.Accounts
        public let fees: Repository.Fees
        public let serverHealth: Repository.ServerHealth
        public let subscriptions: Repository.Subscriptions

        public init(configuration: Configuration) throws {
            self.container = try configuration.makeContainer()

            self.headers = .init(container: container)
            self.utxos = .init(container: container)
            self.transactions = .init(container: container)
            self.accounts = .init(container: container)
            self.fees = .init(container: container)
            self.serverHealth = .init(container: container)
            self.subscriptions = .init(container: container)
        }
    }
}

extension Storage.Facade {
    @inline(__always)
    nonisolated static func withContext<T>(_ container: ModelContainer,
                                           _ body: (ModelContext) throws -> T) rethrows -> T {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = true
        return try body(ctx)
    }
}

extension Storage.Facade {
    enum Error: Swift.Error {
        case containerCreationFailed(Swift.Error)
    }
}

#else

public enum StorageConfig {
    case disk(URL)
    case memory
}

public struct StorageFacade {
    public init(config: StorageConfig = .memory, ttl: TimeInterval = 0) throws {}
}

#endif
