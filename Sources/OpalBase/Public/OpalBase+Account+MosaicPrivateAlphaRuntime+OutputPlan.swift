// OpalBase+Account+MosaicPrivateAlphaRuntime+OutputPlan.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Selects amounts without guessing a contributor's fee share before election.
    @_spi(MosaicPrivateAlpha)
    public enum OutputPlan: Sendable, Equatable {
        /// Preserve the caller's exact output amounts and reject a fee mismatch.
        case exact([UInt64])

        /// Return selected value minus the authenticated roster-derived fee in
        /// one fresh output. The caller supplies its minimum acceptable value.
        case singleValuePreserving(minimumAmountSatoshis: UInt64)
    }
}

extension OpalBase.Account.MosaicPrivateAlphaRuntime.OutputPlan {
    func isValid(for policy: OpalBase.Account.MosaicProfileContributionPolicy) -> Bool {
        switch self {
        case let .exact(amounts):
            return !amounts.isEmpty && amounts.allSatisfy { $0 > 0 }
                && Self.sum(amounts) != nil
        case let .singleValuePreserving(minimum):
            return policy.profile == .opalMainnetAlpha && minimum > 0
        }
    }

    func resolve(
        inputAmountsSatoshis: [UInt64],
        policy: OpalBase.Account.MosaicProfileContributionPolicy,
        requiredExcessFeeSatoshis: UInt64
    ) throws -> [UInt64] {
        switch self {
        case let .exact(amounts):
            return amounts
        case let .singleValuePreserving(minimum):
            guard isValid(for: policy),
                  let inputValue = Self.sum(inputAmountsSatoshis),
                  let contribution = policy.expectedLocalContributionSatoshis(
                    inputCount: inputAmountsSatoshis.count,
                    outputCount: 1,
                    requiredExcessFeeSatoshis: requiredExcessFeeSatoshis
                  ),
                  inputValue >= contribution,
                  inputValue - contribution >= minimum else {
                throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
            }
            return [inputValue - contribution]
        }
    }

    private static func sum(_ values: [UInt64]) -> UInt64? {
        var sum: UInt64 = 0
        for value in values {
            let addition = sum.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            sum = addition.partialValue
        }
        return sum
    }
}
#endif
