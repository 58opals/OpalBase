// OpalBase+WalletPublicChainOperations.swift

public extension OpalBase {
    /// Public-chain operations used by sync, transport, broadcast, and claimable status lanes.
    struct WalletPublicChainOperations: Sendable {
        public let addressReader: OpalBase.Network.AddressReader
        public let transactionClient: OpalBase.Network.TransactionClient
        public let transactionReader: OpalBase.Network.TransactionReader?
        public let blockHeaderReader: OpalBase.Network.BlockHeaderReader?

        public init(
            addressReader: OpalBase.Network.AddressReader,
            transactionClient: OpalBase.Network.TransactionClient,
            transactionReader: OpalBase.Network.TransactionReader? = nil,
            blockHeaderReader: OpalBase.Network.BlockHeaderReader? = nil
        ) {
            self.addressReader = addressReader
            self.transactionClient = transactionClient
            self.transactionReader = transactionReader
            self.blockHeaderReader = blockHeaderReader
        }
    }
}
