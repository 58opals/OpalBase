// OpalBase+WalletTransportInteractor.swift

public extension OpalBase {
    /// Public transport lane for chain readers, broadcast clients, and public streams.
    struct WalletTransportInteractor: Sendable {
        public let publicChain: OpalBase.WalletPublicChainOperations

        public init(publicChain: OpalBase.WalletPublicChainOperations) {
            self.publicChain = publicChain
        }

        public init(
            fulcrumClient: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init(),
            transactionCache: OpalBase.Transaction.Cache = .init()
        ) {
            let addressReader = OpalBase.Network.AddressReader(
                OpalBase.Network.Fulcrum.AddressReader(client: fulcrumClient, timeouts: timeouts)
            )
            let blockHeaderReader = OpalBase.Network.BlockHeaderReader(
                OpalBase.Network.Fulcrum.BlockHeaderReader(client: fulcrumClient, timeouts: timeouts)
            )
            let transactionClient = OpalBase.Network.TransactionClient(
                OpalBase.Network.Fulcrum.TransactionClient(client: fulcrumClient, timeouts: timeouts)
            )
            let transactionReader = OpalBase.Network.TransactionReader(
                OpalBase.Network.Fulcrum.TransactionReader(
                    client: fulcrumClient,
                    timeouts: timeouts,
                    cache: transactionCache
                )
            )
            self.publicChain = .init(
                addressReader: addressReader,
                transactionClient: transactionClient,
                transactionReader: transactionReader,
                blockHeaderReader: blockHeaderReader
            )
        }

        public func subscribeToAddress(
            _ address: OpalBase.Address
        ) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
            try await publicChain.addressReader.subscribeToAddress(address.string)
        }

        public func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>? {
            guard let blockHeaderReader = publicChain.blockHeaderReader else {
                return nil
            }
            return try await blockHeaderReader.subscribeToTip()
        }

        public func makeWalletFulcrumAdapter() -> OpalBase.Wallet.Fulcrum? {
            guard let blockHeaderReader = publicChain.blockHeaderReader else {
                return nil
            }
            return OpalBase.Wallet.Fulcrum(
                addressReader: publicChain.addressReader,
                blockHeaderReader: blockHeaderReader,
                transactionClient: publicChain.transactionClient,
                transactionReader: publicChain.transactionReader
            )
        }
    }
}
