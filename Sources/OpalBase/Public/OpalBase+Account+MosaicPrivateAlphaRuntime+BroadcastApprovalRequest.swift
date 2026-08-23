// OpalBase+Account+MosaicPrivateAlphaRuntime+BroadcastApprovalRequest.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact, reviewable transaction and value context for one recovered broadcast decision.
    @_spi(MosaicPrivateAlpha)
    public struct BroadcastApprovalRequest: Sendable, Equatable {
        /// One canonical transaction output in exact transaction order.
        @_spi(MosaicPrivateAlpha)
        public struct ExpectedOutput: Sendable, Equatable {
            @_spi(MosaicPrivateAlpha)
            public let valueSatoshis: UInt64

            @_spi(MosaicPrivateAlpha)
            public let lockingScript: Data

            @_spi(MosaicPrivateAlpha)
            public let serializedBytes: Data

            init?(_ output: OpalBase.Transaction.Output) {
                guard let serializedBytes = try? output.encode() else {
                    return nil
                }
                valueSatoshis = output.value
                lockingScript = Data(output.lockingScript)
                self.serializedBytes = serializedBytes
            }
        }

        @_spi(MosaicPrivateAlpha)
        public let transactionBytes: Data

        @_spi(MosaicPrivateAlpha)
        public let transactionHash: OpalBase.Transaction.Hash

        @_spi(MosaicPrivateAlpha)
        public let transactionSizeBytes: UInt32

        @_spi(MosaicPrivateAlpha)
        public let network: OpalBase.Network.Environment

        @_spi(MosaicPrivateAlpha)
        public let profile: Profile

        @_spi(MosaicPrivateAlpha)
        public let walletReservationIdentifier: UUID

        @_spi(MosaicPrivateAlpha)
        public let walletGeneration: UInt64

        @_spi(MosaicPrivateAlpha)
        public let expectedNetworkGenesisHash: Data

        @_spi(MosaicPrivateAlpha)
        public let reservationExpiresAt: Date

        @_spi(MosaicPrivateAlpha)
        public let expectedOutputs: [ExpectedOutput]

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
                  let expectedOutputs = Self.makeExpectedOutputs(
                    exactTransaction.transaction.outputs
                  ),
                  Self.sumSatoshis(
                    expectedOutputs.map(\.valueSatoshis)
                  ) == totalOutputSatoshis else {
                return nil
            }
            transactionBytes = exactTransaction.bytes
            transactionHash = exactTransaction.hash
            self.transactionSizeBytes = transactionSizeBytes
            network = request.network
            profile = .init(request.profile)
            walletReservationIdentifier = request.reservationReference
                .identifier
            walletGeneration = request.reservationReference.generation
            expectedNetworkGenesisHash = Data(
                request.reservationRequest.networkGenesisHash
            )
            reservationExpiresAt = request.reservationRequest.expiresAt
            self.expectedOutputs = expectedOutputs
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

        private static func makeExpectedOutputs(
            _ outputs: [OpalBase.Transaction.Output]
        ) -> [ExpectedOutput]? {
            var expectedOutputs: [ExpectedOutput] = []
            expectedOutputs.reserveCapacity(outputs.count)
            for output in outputs {
                guard let expectedOutput = ExpectedOutput(output) else {
                    return nil
                }
                expectedOutputs.append(expectedOutput)
            }
            return expectedOutputs
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
