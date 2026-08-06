// MosaicPolicyProbeActor.swift

#if os(macOS)
@testable import OpalBase

actor MosaicPolicyProbeActor {
    private let expectedFeeSatoshis: UInt64?
    private let rejectsProposal: Bool
    private var invocationCount = 0

    init(
        expectedFeeSatoshis: UInt64? = nil,
        rejectsProposal: Bool = false
    ) {
        self.expectedFeeSatoshis = expectedFeeSatoshis
        self.rejectsProposal = rejectsProposal
    }

    func validate(feeSatoshis: UInt64) throws {
        invocationCount += 1
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
        .init { [self] _, _, feeSatoshis in
            try await validate(feeSatoshis: feeSatoshis)
        }
    }
}
#endif
