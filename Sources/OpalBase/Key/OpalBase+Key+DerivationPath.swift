// OpalBase+Key+DerivationPath.swift

import Foundation

extension _OpalBase.Key {
    public struct DerivationPath: Hashable, Sendable {
        public let purpose: Purpose
        public let coinType: CoinType
        public var account: Account
        public let usage: Usage
        public let index: UInt32

        public init(
            purpose: Purpose = .bip44,
            coinType: CoinType = .bitcoinCash,
            account: Account,
            usage: Usage,
            index: UInt32
        ) throws {
            guard index <= Harden.maxUnhardenedValue else { throw Error.indexOverflow }

            self.purpose = purpose
            self.coinType = coinType
            self.account = account
            self.usage = usage
            self.index = index
        }

        public func makeIndices() throws -> [UInt32] {
            let accountIndex = try account.deriveHardenedIndex()
            return [
                purpose.hardenedIndex,
                coinType.hardenedIndex,
                accountIndex,
                usage.unhardenedIndex,
                index
            ]
        }

        public var path: String {
            "m/\(purpose.unhardenedIndex)'/\(coinType.unhardenedIndex)'/\(account.unhardenedIndex)'/\(usage.unhardenedIndex)/\(index)"
        }
    }
}
