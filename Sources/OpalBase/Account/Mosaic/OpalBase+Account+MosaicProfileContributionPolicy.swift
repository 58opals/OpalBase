// OpalBase+Account+MosaicProfileContributionPolicy.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    /// Exact wallet-side fee terms for the two explicitly supported Mosaic profiles.
    struct MosaicProfileContributionPolicy: Sendable, Equatable {
        private static let mainnetAlphaProfileIdentifier =
            "Mosaic/0-opal-mainnet-alpha.4"
        private static let mainnetAlphaTransactionProfileIdentifier =
            "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4"

        let profile: OpalFusion.Mosaic.Profile
        let feeRateSatoshisPerByte: UInt64
        let minimumExcessFeeSatoshis: UInt64
        let maximumExcessFeeSatoshis: UInt64

        init?(profile: OpalFusion.Mosaic.Profile) {
            self.profile = profile
            switch profile {
            case .opalV0:
                feeRateSatoshisPerByte = 1
                minimumExcessFeeSatoshis = 0
                maximumExcessFeeSatoshis = 0
            case .opalMainnetAlpha:
                guard profile.rawValue == Self.mainnetAlphaProfileIdentifier,
                      profile.transactionProfileIdentifier
                        == Self.mainnetAlphaTransactionProfileIdentifier else {
                    return nil
                }
                feeRateSatoshisPerByte = 1
                minimumExcessFeeSatoshis = 1
                maximumExcessFeeSatoshis = 2
            case .draft1:
                return nil
            }
        }

        func accepts(
            feeRateSatoshisPerByte: UInt64,
            minimumExcessFeeSatoshis: UInt64,
            maximumExcessFeeSatoshis: UInt64,
            requiredExcessFeeSatoshis: UInt64
        ) -> Bool {
            feeRateSatoshisPerByte == self.feeRateSatoshisPerByte
                && minimumExcessFeeSatoshis == self.minimumExcessFeeSatoshis
                && maximumExcessFeeSatoshis == self.maximumExcessFeeSatoshis
                && (minimumExcessFeeSatoshis ... maximumExcessFeeSatoshis)
                    .contains(requiredExcessFeeSatoshis)
        }

        func matchesLocalContribution(
            inputAmountsSatoshis: [UInt64],
            outputAmountsSatoshis: [UInt64],
            requiredExcessFeeSatoshis: UInt64
        ) -> Bool {
            guard profile == .opalMainnetAlpha else {
                return profile == .opalV0
            }
            guard let inputValue = Self.sum(inputAmountsSatoshis),
                  let outputValue = Self.sum(outputAmountsSatoshis),
                  inputValue >= outputValue,
                  let expectedContribution = expectedLocalContributionSatoshis(
                    inputCount: inputAmountsSatoshis.count,
                    outputCount: outputAmountsSatoshis.count,
                    requiredExcessFeeSatoshis: requiredExcessFeeSatoshis
                  ) else {
                return false
            }
            return inputValue - outputValue == expectedContribution
        }

        func expectedLocalContributionSatoshis(
            inputCount: Int,
            outputCount: Int,
            requiredExcessFeeSatoshis: UInt64
        ) -> UInt64? {
            guard profile == .opalMainnetAlpha,
                  (minimumExcessFeeSatoshis ... maximumExcessFeeSatoshis)
                    .contains(requiredExcessFeeSatoshis),
                  let inputCount = UInt64(exactly: inputCount),
                  let outputCount = UInt64(exactly: outputCount),
                  let inputFee = Self.multiply(141, by: inputCount),
                  let outputFee = Self.multiply(34, by: outputCount),
                  let componentFee = Self.add(inputFee, outputFee) else {
                return nil
            }
            return Self.add(componentFee, requiredExcessFeeSatoshis)
        }

        private static func sum(_ values: [UInt64]) -> UInt64? {
            var total: UInt64 = 0
            for value in values {
                let result = total.addingReportingOverflow(value)
                guard !result.overflow else { return nil }
                total = result.partialValue
            }
            return total
        }

        private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64? {
            let result = lhs.addingReportingOverflow(rhs)
            return result.overflow ? nil : result.partialValue
        }

        private static func multiply(_ lhs: UInt64, by rhs: UInt64) -> UInt64? {
            let result = lhs.multipliedReportingOverflow(by: rhs)
            return result.overflow ? nil : result.partialValue
        }
    }
}
#endif
