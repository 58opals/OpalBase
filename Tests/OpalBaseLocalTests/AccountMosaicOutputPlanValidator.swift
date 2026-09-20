// AccountMosaicOutputPlanValidator.swift

#if os(macOS)
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("Mosaic output planning", .tags(.unit, .wallet))
struct AccountMosaicOutputPlanValidator {
    typealias Plan = OpalBase.Account.MosaicPrivateAlphaRuntime.OutputPlan

    @Test("Election-derived fee shares preserve the complete input value")
    func resolveBothRosterShares() throws {
        let policy = try #require(OpalBase.Account.MosaicProfileContributionPolicy(
            profile: .opalMainnetAlpha
        ))
        let plan = Plan.singleValuePreserving(minimumAmountSatoshis: 546)
        var outputs: UInt64 = 0
        for share: UInt64 in [2, 2, 2, 2, 1, 1] {
            let amounts = try plan.resolve(
                inputAmountsSatoshis: [1_000], policy: policy,
                requiredExcessFeeSatoshis: share
            )
            #expect(amounts == [1_000 - 175 - share])
            #expect(policy.matchesLocalContribution(
                inputAmountsSatoshis: [1_000], outputAmountsSatoshis: amounts,
                requiredExcessFeeSatoshis: share
            ))
            outputs += amounts[0]
        }
        #expect(6_000 - outputs == 1_060)
        #expect(try Plan.exact([800]).resolve(
            inputAmountsSatoshis: [1_000], policy: policy,
            requiredExcessFeeSatoshis: 2
        ) == [800])
    }

    @Test("Unsafe minimums, unsupported shares and insufficient value fail closed")
    func rejectUnsafePlans() throws {
        let policy = try #require(OpalBase.Account.MosaicProfileContributionPolicy(
            profile: .opalMainnetAlpha
        ))
        let plan = Plan.singleValuePreserving(minimumAmountSatoshis: 546)
        for inputs: [UInt64] in [[], [0], [176], [722], [.max, 1]] {
            #expect(throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy) {
                try plan.resolve(inputAmountsSatoshis: inputs, policy: policy,
                                 requiredExcessFeeSatoshis: 2)
            }
        }
        #expect(try plan.resolve(inputAmountsSatoshis: [723], policy: policy,
                                 requiredExcessFeeSatoshis: 2) == [546])
        for share: UInt64 in [0, 3, .max] {
            #expect(throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy) {
                try plan.resolve(inputAmountsSatoshis: [1_000], policy: policy,
                                 requiredExcessFeeSatoshis: share)
            }
        }
        #expect(!Plan.singleValuePreserving(minimumAmountSatoshis: 0).isValid(for: policy))
        let chipnetPolicy = try #require(OpalBase.Account.MosaicProfileContributionPolicy(
            profile: .opalV0
        ))
        #expect(!plan.isValid(for: chipnetPolicy))
        #expect(!Plan.exact([]).isValid(for: policy))
        #expect(!Plan.exact([0]).isValid(for: policy))
        #expect(!Plan.exact([.max, 1]).isValid(for: policy))
    }

    @Test("Reservation resolves the assigned share once and journals exact amounts",
          arguments: [UInt64(1), 2])
    func reserveWithElectedShare(share: UInt64) async throws {
        let policy = OpalBase.Account.MosaicTransactionPolicy(
            profile: .opalMainnetAlpha, network: .mainnet
        ) { _, _, _ in }
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy, network: .mainnet, profile: .opalMainnetAlpha,
            requiredExcessFeeSatoshis: share,
            outputPlan: .singleValuePreserving(minimumAmountSatoshis: 546)
        )
        let lease = try await fixture.reserve()
        #expect(lease.participantReservation.outputs.map(\.amountSatoshis)
                == [100_000 - 175 - share])
        #expect(try await fixture.reserve() == lease)
        let records = await fixture.journalProbe.readRecords()
        let planned = records.compactMap { record -> [UInt64]? in
            guard case let .reservationPrepared(_, _, amounts, _) = record else { return nil }
            return amounts
        }
        #expect(planned == [[100_000 - 175 - share]])
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }
}
#endif
