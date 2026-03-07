// OpalBase+DerivationPath+Error.swift

import Foundation

extension OpalBase {
    public struct DerivationPath: Hashable, Sendable {
        public let purpose: PurposeModel
        public let coinType: CoinTypeModel
        public var account: Account
        public let usage: UsageModel
        public let index: UInt32

        public init(
            purpose: PurposeModel = .bip44,
            coinType: CoinTypeModel = .bitcoinCash,
            account: Account,
            usage: UsageModel,
            index: UInt32
        ) throws {
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

extension _OpalBase.DerivationPath {
    enum Error: Swift.Error {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}
