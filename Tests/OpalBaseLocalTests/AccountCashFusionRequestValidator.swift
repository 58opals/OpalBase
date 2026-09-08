// AccountCashFusionRequestValidator.swift

#if os(macOS)
import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion request", .tags(.unit, .wallet))
struct AccountCashFusionRequestValidator {
    @Test("request retains selected inputs and output amounts")
    func requestRetainsSelectedInputsAndOutputAmounts() throws {
        let selectedInput = try Self.makeSelectedInput(value: 120_000, hashByte: 0xA1)
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
        #expect(request.outputPolicy == .explicitAmounts(outputAmounts))
    }

    @Test("request supports value-preserving output policy")
    func requestSupportsValuePreservingOutputPolicy() throws {
        let selectedInput = try Self.makeSelectedInput(value: 150_000, hashByte: 0xA3)

        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [selectedInput],
            outputPolicy: .valuePreserving
        )

        #expect(request.selectedInputs == [selectedInput])
        #expect(request.outputAmounts.isEmpty)
        #expect(request.outputPolicy == .valuePreserving)
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
            request: request
        )

        #expect(await session.makePublicStatus() == .init(
            isConnected: false,
            round: nil,
            lastError: nil
        ))

        await session.stop()
    }

    private static func makeSelectedInput(
        value: UInt64,
        hashByte: UInt8
    ) throws -> OpalBase.Transaction.Output.Unspent {
        OpalBase.Transaction.Output.Unspent(
            value: value,
            lockingScript: try OpalBase.Address(string: AccountTestFixtures.standardAddressString).lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: hashByte),
            previousTransactionOutputIndex: 0
        )
    }

}
#endif
