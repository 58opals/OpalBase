// OpalBase+Account+MosaicPrivateAlphaRuntime+BroadcastApprovalRequest.swift

#if os(macOS)
import Foundation
import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact, reviewable transaction and value context for one recovered broadcast decision.
    @_spi(MosaicPrivateAlpha)
    public struct BroadcastApprovalRequest: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha)
        public let transactionBytes: Data

        @_spi(MosaicPrivateAlpha)
        public let transactionHash: OpalBase.Transaction.Hash

        @_spi(MosaicPrivateAlpha)
        public let transactionSizeBytes: UInt32

        @_spi(MosaicPrivateAlpha)
        public let network: OpalBase.Network.Environment

        @_spi(MosaicPrivateAlpha)
        public let profile: OpalFusion.Mosaic.Profile

        @_spi(MosaicPrivateAlpha)
        public let reservationExpiresAt: Date

        @_spi(MosaicPrivateAlpha)
        public let totalInputSatoshis: UInt64

        @_spi(MosaicPrivateAlpha)
        public let totalOutputSatoshis: UInt64

        @_spi(MosaicPrivateAlpha)
        public let feeSatoshis: UInt64

        @_spi(MosaicPrivateAlpha)
        public let feeRateSatoshisPerByte: UInt64

        @_spi(MosaicPrivateAlpha)
        public let minimumExcessFeeSatoshis: UInt64

        @_spi(MosaicPrivateAlpha)
        public let maximumExcessFeeSatoshis: UInt64

        @_spi(MosaicPrivateAlpha)
        public let requiredExcessFeeSatoshis: UInt64

        init?(
            _ request: OpalBase.Account
                .MosaicTransactionBroadcastCoordinator.ApprovalRequest
        ) {
            guard let totalInputSatoshis = request.totalInputSatoshis,
                  let totalOutputSatoshis = request.totalOutputSatoshis,
                  let feeSatoshis = request.feeSatoshis,
                  totalInputSatoshis >= totalOutputSatoshis,
                  totalInputSatoshis - totalOutputSatoshis == feeSatoshis,
                  let exactTransaction = try? OpalBase.Account
                    .MosaicExactTransaction(request.completeTransaction),
                  let transactionSizeBytes = UInt32(
                    exactly: exactTransaction.bytes.count
                  ),
                  Self.sumSatoshis(
                    exactTransaction.transaction.outputs.map(\.value)
                  ) == totalOutputSatoshis else {
                return nil
            }
            transactionBytes = exactTransaction.bytes
            transactionHash = exactTransaction.hash
            self.transactionSizeBytes = transactionSizeBytes
            network = request.network
            profile = request.profile
            reservationExpiresAt = request.reservationRequest.expiresAt
            self.totalInputSatoshis = totalInputSatoshis
            self.totalOutputSatoshis = totalOutputSatoshis
            self.feeSatoshis = feeSatoshis
            feeRateSatoshisPerByte = request.reservationRequest
                .feeRateSatoshisPerByte
            minimumExcessFeeSatoshis = request.reservationRequest
                .minimumExcessFeeSatoshis
            maximumExcessFeeSatoshis = request.reservationRequest
                .maximumExcessFeeSatoshis
            requiredExcessFeeSatoshis = request.reservationRequest
                .requiredExcessFeeSatoshis
        }

        private static func sumSatoshis(
            _ values: [UInt64]
        ) -> UInt64? {
            var total: UInt64 = 0
            for value in values {
                let addition = total.addingReportingOverflow(value)
                guard !addition.overflow else { return nil }
                total = addition.partialValue
            }
            return total
        }
    }
}
#endif
