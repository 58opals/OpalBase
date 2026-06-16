// SpendPlanBroadcastAccountFixture.swift

import OpalCrypto
import OpalBaseTestSupport
@testable import OpalBase

enum SpendPlanBroadcastAccountFixture {
    static func makeAccountWithoutOutputRandomization() async throws -> OpalBase.Account {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        return try await OpalBase.Account(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            privacyConfiguration: .init(
                batchingIntervalRange: 0 ... 0,
                operationJitterRange: 0 ... 0,
                decoyQueryRange: 0 ... 0,
                decoyProbability: 0,
                shouldRandomizeUTXOOrdering: false,
                shouldRandomizeRecipientOrdering: false
            )
        )
    }
}
