// OpalBase+Account+MosaicTransactionHostActor.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Mainnet-disabled wallet authority for one non-resumable Mosaic attempt.
    actor MosaicTransactionHostActor: OpalFusion.Host.MosaicTransactionHost {
        let addressBook: OpalBase.Address.Book
        let expectedNetworkGenesisHash: [UInt8]
        let generation: UInt64
        let selectedInputs: [OpalBase.Transaction.Output.Unspent]
        let outputAmountsSatoshis: [UInt64]
        let transactionPolicy: MosaicTransactionPolicy
        let currentDate: @Sendable () -> Date
        let makeReservationIdentifier: @Sendable () -> UUID
        let reserveReceivingEntry: @Sendable (
            OpalBase.Address.Book
        ) async throws -> OpalBase.Address.Book.Entry
        let sleepUntilDate: @Sendable (Date) async throws -> Void

        var reservationRequest: OpalFusion.Host.MosaicReservationRequest?
        var reservationLease: OpalFusion.Host.MosaicReservationLease?
        var reservedInputs: [MosaicReservedInputRecord] = []
        var reservedReceivingEntries: [OpalBase.Address.Book.Entry] = []
        var expirationTask: Task<Void, Never>?
        var releaseStarted = false
        var commitStarted = false
        var isReleased = false
        var finalizedRequest: OpalFusion.Host.MosaicTransactionSigningRequest?
        var finalizedTransaction: OpalFusion.Host.FinalizedTransaction?
        var committedTransaction: OpalFusion.Host.FinalizedTransaction?
        var signingInvocationCount = 0

        init(
            addressBook: OpalBase.Address.Book,
            network: OpalBase.Network.Environment,
            generation: UInt64,
            selectedInputs: [OpalBase.Transaction.Output.Unspent],
            outputAmountsSatoshis: [UInt64],
            transactionPolicy: MosaicTransactionPolicy,
            currentDate: @escaping @Sendable () -> Date = Date.init,
            makeReservationIdentifier: @escaping @Sendable () -> UUID = UUID.init,
            reserveReceivingEntry: @escaping @Sendable (
                OpalBase.Address.Book
            ) async throws -> OpalBase.Address.Book.Entry = { addressBook in
                try await addressBook.reserveMosaicReceivingEntry()
            },
            sleepUntilDate: @escaping @Sendable (Date) async throws -> Void = { deadline in
                let interval = deadline.timeIntervalSinceNow
                guard interval > 0 else { return }
                try await Task.sleep(for: .seconds(interval))
            }
        ) throws {
            guard network != .mainnet else {
                throw MosaicHostFailure.mainnetUnavailable
            }
            guard !selectedInputs.isEmpty,
                  Set(selectedInputs).count == selectedInputs.count,
                  selectedInputs.allSatisfy({ $0.tokenData == nil }),
                  !outputAmountsSatoshis.isEmpty,
                  outputAmountsSatoshis.allSatisfy({ $0 > 0 }),
                  Self.sum(outputAmountsSatoshis) != nil,
                  Self.sum(selectedInputs.map(\.value)) != nil else {
                throw MosaicHostFailure.invalidContributionPolicy
            }

            self.addressBook = addressBook
            self.expectedNetworkGenesisHash = network.mosaicGenesisHash
            self.generation = generation
            self.selectedInputs = selectedInputs
            self.outputAmountsSatoshis = outputAmountsSatoshis
            self.transactionPolicy = transactionPolicy
            self.currentDate = currentDate
            self.makeReservationIdentifier = makeReservationIdentifier
            self.reserveReceivingEntry = reserveReceivingEntry
            self.sleepUntilDate = sleepUntilDate
        }

        deinit {
            expirationTask?.cancel()
        }

        func readSigningInvocationCount() -> Int {
            signingInvocationCount
        }

        private static func sum(_ values: [UInt64]) -> UInt64? {
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
