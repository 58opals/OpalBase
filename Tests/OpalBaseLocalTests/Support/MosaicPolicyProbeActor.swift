// MosaicPolicyProbeActor.swift

#if os(macOS)
import OpalFusion
@testable import OpalBase

actor MosaicPolicyProbeActor {
    private let expectedFeeSatoshis: UInt64?
    private let rejectsProposal: Bool
    private let suspensionProbe: MosaicOperationSuspensionProbeActor?
    private var invocationCount = 0

    init(
        expectedFeeSatoshis: UInt64? = nil,
        rejectsProposal: Bool = false,
        suspensionProbe: MosaicOperationSuspensionProbeActor? = nil
    ) {
        self.expectedFeeSatoshis = expectedFeeSatoshis
        self.rejectsProposal = rejectsProposal
        self.suspensionProbe = suspensionProbe
    }

    func validate(feeSatoshis: UInt64) async throws {
        invocationCount += 1
        if let suspensionProbe {
            await suspensionProbe.suspend()
        }
        if let expectedFeeSatoshis, expectedFeeSatoshis != feeSatoshis {
            throw MosaicPolicyFixtureFailure.unexpectedFee
        }
        if rejectsProposal {
            throw MosaicPolicyFixtureFailure.rejected
        }
    }

    func readInvocationCount() -> Int {
        invocationCount
    }

    var transactionPolicy: OpalBase.Account.MosaicTransactionPolicy {
        makeTransactionPolicy()
    }

    func makeTransactionPolicy(
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        network: OpalBase.Network.Environment = .chipnet
    ) -> OpalBase.Account.MosaicTransactionPolicy {
        .init(profile: profile, network: network) { [self] _, _, feeSatoshis in
            try await validate(feeSatoshis: feeSatoshis)
        }
    }
}
#endif
