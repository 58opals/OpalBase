// OpalBase+WalletReceiveAddressInteractor.swift

public extension OpalBase {
    /// Receive-address lane for derivation, reservation, and address cache validity.
    struct WalletReceiveAddressInteractor: Sendable {
        private let account: OpalBase.Account

        public init(account: OpalBase.Account) {
            self.account = account
        }

        public init(accountDescriptor: OpalBase.WalletAccountPublicDescriptor) async throws {
            self.account = try await accountDescriptor.makeReadOnlyAccount()
        }

        public func listDerivedAddresses(
            for usage: OpalBase.Key.DerivationPath.Usage
        ) async -> [OpalBase.Account.DerivedAddress] {
            await account.listDerivedAddresses(for: usage)
        }

        public func selectNextDerivedAddress(
            for usage: OpalBase.Key.DerivationPath.Usage
        ) async throws -> OpalBase.Account.DerivedAddress {
            try await account.selectNextDerivedAddress(for: usage)
        }

        public func reserveNextReceivingDerivedAddress() async throws -> OpalBase.Account.DerivedAddress {
            try await account.reserveNextReceivingDerivedAddress()
        }

        public func makeSnapshot() async -> OpalBase.Account.Snapshot {
            await account.makeSnapshot()
        }
    }
}
