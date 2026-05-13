// OpalBase+Account+CashFusionSession+Configuration.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.CashFusionSession {
    public struct Configuration: Sendable, Equatable {
        public struct Coordinator: Sendable, Equatable {
            public let host: String
            public let port: UInt16
            public let requiresTLS: Bool

            public init(
                host: String,
                port: UInt16,
                requiresTLS: Bool = false
            ) {
                self.host = host
                self.port = port
                self.requiresTLS = requiresTLS
            }
        }

        public struct CovertChannel: Sendable, Equatable {
            public let entryPath: String
            public let maxPayloadBytes: Int
            public let requestTimeoutMilliseconds: UInt64

            public init(
                entryPath: String,
                maxPayloadBytes: Int,
                requestTimeoutMilliseconds: UInt64
            ) {
                self.entryPath = entryPath
                self.maxPayloadBytes = maxPayloadBytes
                self.requestTimeoutMilliseconds = requestTimeoutMilliseconds
            }
        }

        public struct TorSocks5: Sendable, Equatable {
            public let host: String
            public let port: UInt16
            public let resolvesCoordinatorHostNameRemotely: Bool

            public init(
                host: String,
                port: UInt16,
                resolvesCoordinatorHostNameRemotely: Bool = true
            ) {
                self.host = host
                self.port = port
                self.resolvesCoordinatorHostNameRemotely = resolvesCoordinatorHostNameRemotely
            }
        }

        public struct PoolTag: Sendable, Equatable {
            public let identifier: [UInt8]
            public let limit: UInt32
            public let noIp: Bool?

            public init(
                identifier: [UInt8],
                limit: UInt32,
                noIp: Bool? = nil
            ) {
                self.identifier = identifier
                self.limit = limit
                self.noIp = noIp
            }
        }

        public struct JoinPools: Sendable, Equatable {
            public let tiers: [UInt64]
            public let tags: [PoolTag]

            public init(
                tiers: [UInt64],
                tags: [PoolTag]
            ) {
                self.tiers = tiers
                self.tags = tags
            }
        }

        public let coordinator: Coordinator
        public let covertChannel: CovertChannel
        public let torSocks5: TorSocks5?
        public let genesisHash: [UInt8]?
        public let joinPools: JoinPools

        public init(
            coordinator: Coordinator,
            covertChannel: CovertChannel,
            torSocks5: TorSocks5? = nil,
            genesisHash: [UInt8]? = nil,
            joinPools: JoinPools
        ) {
            self.coordinator = coordinator
            self.covertChannel = covertChannel
            self.torSocks5 = torSocks5
            self.genesisHash = genesisHash
            self.joinPools = joinPools
        }
    }
}
#endif
