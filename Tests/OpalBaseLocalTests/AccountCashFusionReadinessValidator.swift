// AccountCashFusionReadinessValidator.swift

#if os(macOS)
import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion readiness", .tags(.unit, .wallet))
struct AccountCashFusionReadinessValidator {
    @Test("ready account reports pilot availability and eligible UTXOs")
    func readyAccountReportsPilotAvailabilityAndEligibleUTXOs() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let eligibleUTXO = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 150_000,
            usage: .change,
            hashByte: 0xC1
        )

        let readiness = try await account.evaluateCashFusionReadiness()

        #expect(readiness.pilotAvailability == .available)
        #expect(readiness.accountStatus == .ready)
        #expect(readiness.utxoEligibility.count == 1)

        let eligibility = try #require(readiness.utxoEligibility.first)
        #expect(eligibility.unspentOutput == eligibleUTXO)
        #expect(eligibility.status == .eligible)
    }

    @Test("account with no spendable UTXOs is blocked for no eligible UTXOs")
    func accountWithNoSpendableUTXOsIsBlockedForNoEligibleUTXOs() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let readiness = try await account.evaluateCashFusionReadiness()

        #expect(readiness.pilotAvailability == .available)
        #expect(readiness.accountStatus == .blocked(.noEligibleUTXOs))
        #expect(readiness.utxoEligibility.isEmpty)
    }

    @Test("token UTXOs are reported as blocked")
    func tokenUTXOsAreReportedAsBlocked() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let tokenUTXO = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: CashFusionTestSupport.makeTokenData(),
            usage: .change,
            hashByte: 0xC2
        )

        let readiness = try await account.evaluateCashFusionReadiness()

        #expect(readiness.accountStatus == .blocked(.noEligibleUTXOs))
        #expect(readiness.utxoEligibility.count == 1)

        let eligibility = try #require(readiness.utxoEligibility.first)
        #expect(eligibility.unspentOutput == tokenUTXO)
        #expect(eligibility.status == .blocked(.tokenUTXO))
    }

    @Test("unsupported locking scripts are reported as blocked")
    func unsupportedLockingScriptsAreReportedAsBlocked() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let unsupportedUTXO = OpalBase.Transaction.Output.Unspent(
            value: 130_000,
            lockingScript: Data([0x51]),
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0xC3, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let addressBook = await account.addressBook
        await addressBook.addUTXO(unsupportedUTXO)

        let readiness = try await account.evaluateCashFusionReadiness()

        #expect(readiness.accountStatus == .blocked(.noEligibleUTXOs))
        #expect(readiness.utxoEligibility.count == 1)

        let eligibility = try #require(readiness.utxoEligibility.first)
        #expect(eligibility.unspentOutput == unsupportedUTXO)
        #expect(eligibility.status == .blocked(.unsupportedLockingScript))
    }
}
#endif
