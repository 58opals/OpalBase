// OpalBase+WalletAccountPublicDescriptor.swift

public extension OpalBase {
    /// Public account state used by sync and receive-address lanes without mnemonic, Keychain, or Secure Enclave authority.
    struct WalletAccountPublicDescriptor: Codable, Equatable, Hashable, Sendable {
        public let serializedAccountExtendedPublicKey: String
        public let purpose: OpalBase.Key.DerivationPath.Purpose
        public let coinType: OpalBase.Key.DerivationPath.CoinType
        public let accountUnhardenedIndex: UInt32
        public let snapshot: OpalBase.Account.Snapshot

        public init(
            serializedAccountExtendedPublicKey: String,
            purpose: OpalBase.Key.DerivationPath.Purpose,
            coinType: OpalBase.Key.DerivationPath.CoinType,
            accountUnhardenedIndex: UInt32,
            snapshot: OpalBase.Account.Snapshot
        ) {
            self.serializedAccountExtendedPublicKey = serializedAccountExtendedPublicKey
            self.purpose = purpose
            self.coinType = coinType
            self.accountUnhardenedIndex = accountUnhardenedIndex
            self.snapshot = snapshot
        }

        public func makeReadOnlyAccount() async throws -> OpalBase.Account {
            try await OpalBase.Account(
                serializedAccountExtendedPublicKey: serializedAccountExtendedPublicKey,
                purpose: purpose,
                coinType: coinType,
                account: accountUnhardenedIndex,
                snapshot: snapshot
            )
        }
    }
}
