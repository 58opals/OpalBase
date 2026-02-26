// DerivationPathModel.swift

import Foundation

public struct DerivationPathModel: Hashable, Sendable {
    public let purpose: PurposeModel
    public let coinType: CoinTypeModel
    public var account: AccountActor
    public let usage: UsageModel
    public let index: UInt32

    public init(purpose: PurposeModel = .bip44,
                coinType: CoinTypeModel = .bitcoinCash,
                account: AccountActor,
                usage: UsageModel,
                index: UInt32) throws {
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

extension DerivationPathModel {
    enum Error: Swift.Error {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}
