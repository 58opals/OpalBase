// AccountCashFusionRequestValidator.swift

import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion request", .tags(.unit, .wallet))
struct AccountCashFusionRequestValidator {
    @Test("request retains selected inputs and output amounts")
    func requestRetainsSelectedInputsAndOutputAmounts() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xA1
        )
        let outputAmounts = [
            try OpalBase.Satoshi(45_000),
            try OpalBase.Satoshi(30_000)
        ]

        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [selectedInput],
            outputAmounts: outputAmounts
        )

        #expect(request.selectedInputs == [selectedInput])
        #expect(request.outputAmounts == outputAmounts)
    }

    @Test("account prepares the public CashFusion session facade")
    func accountPreparesThePublicCashFusionSessionFacade() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 180_000,
            usage: .change,
            hashByte: 0xA2
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [selectedInput],
            outputAmounts: [try OpalBase.Satoshi(60_000)]
        )

        let session = try await account.prepareCashFusionSession(
            configuration: CashFusionTestSupport.makeConfiguration(),
            joinPools: CashFusionTestSupport.makeJoinPools(),
            request: request
        )

        #expect(await session.snapshot() == .init())

        await session.stop()
    }
}
