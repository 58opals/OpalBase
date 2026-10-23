// SpendPlanBroadcastAccountFixture.swift

import OpalCrypto
import OpalBaseTestSupport
@testable import OpalBase
@testable import OpalBaseCore

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
                shouldRandomizeUTXOOrdering: false,
                shouldRandomizeRecipientOrdering: false
            )
        )
    }
}
