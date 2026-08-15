// OpalBase+Account+MosaicTransactionHostActor.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Profile-bound wallet authority for one non-resumable Mosaic attempt.
    actor MosaicTransactionHostActor: OpalFusion.Host.MosaicCompleteTransactionHost {
        enum Lifecycle: Sendable, Equatable {
            case idle
            case reservationPrepared
            case reserved
            case finalizationPending
            case validating
            case signingIntent
            case localSignaturePending
            case localSignaturePersisting
            case locallySigned
            case commitPending
            case commitIntentPersisting
            case commitRecovery
            case committing
            case committed
            case releaseIntent
            case released
        }

        let addressBook: OpalBase.Address.Book
        let expectedNetworkGenesisHash: [UInt8]
        let profile: OpalFusion.Mosaic.Profile
        let attemptBinding: MosaicAttemptBinding
        let selectedInputs: [OpalBase.Transaction.Output.Unspent]
        let outputAmountsSatoshis: [UInt64]
        let contributionPolicy: MosaicProfileContributionPolicy
        let transactionPolicy: MosaicTransactionPolicy
        let attemptJournal: MosaicAttemptJournal
        let broadcastCoordinatorClaim = MosaicCommittedBroadcastCandidate
            .CoordinatorClaim()
        let currentDate: @Sendable () -> Date
        let reserveReceivingEntry: @Sendable (
            OpalBase.Address.Book,
            OpalBase.Address.Book.Entry
        ) async throws -> OpalBase.Address.Book.Entry
        let sleepUntilDate: @Sendable (Date) async throws -> Void

        var reservationRequest: OpalFusion.Host.MosaicReservationRequest?
        var reservationLease: OpalFusion.Host.MosaicReservationLease?
        var reservedInputs: [MosaicReservedInputRecord] = []
        var reservedReceivingEntries: [OpalBase.Address.Book.Entry] = []
        var expirationTask: Task<Void, Never>?
        var lifecycle: Lifecycle = .idle
        var pendingFinalizationRequest: OpalFusion.Host.MosaicTransactionSigningRequest?
        var finalizedRequest: OpalFusion.Host.MosaicTransactionSigningRequest?
        var finalizedTransaction: OpalFusion.Host.FinalizedTransaction?
        var pendingCompleteTransaction: OpalFusion.Host.MosaicCompleteTransaction?
        var committedCompleteTransaction: OpalFusion.Host.MosaicCompleteTransaction?
        var signingInvocationCount = 0

        init(
            addressBook: OpalBase.Address.Book,
            profile: OpalFusion.Mosaic.Profile,
            network: OpalBase.Network.Environment,
            attemptBinding: MosaicAttemptBinding,
            selectedInputs: [OpalBase.Transaction.Output.Unspent],
            outputAmountsSatoshis: [UInt64],
            transactionPolicy: MosaicTransactionPolicy,
            attemptJournal: MosaicAttemptJournal,
            currentDate: @escaping @Sendable () -> Date = Date.init,
            reserveReceivingEntry: @escaping @Sendable (
                OpalBase.Address.Book,
                OpalBase.Address.Book.Entry
            ) async throws -> OpalBase.Address.Book.Entry = {
                addressBook,
                plannedEntry in
                try await addressBook.reserveMosaicReceivingEntry(
                    plannedEntry
                )
            },
            sleepUntilDate: @escaping @Sendable (Date) async throws -> Void = { deadline in
                let interval = deadline.timeIntervalSinceNow
                guard interval > 0 else { return }
                try await Task.sleep(for: .seconds(interval))
            }
        ) throws {
            guard let contributionPolicy = MosaicProfileContributionPolicy(
                profile: profile
            ),
                  network.supportsMosaicProfile(profile),
                  profile.networkGenesisHash == network.mosaicGenesisHash,
                  transactionPolicy.profile == profile,
                  transactionPolicy.network == network else {
                throw MosaicHostFailure.invalidProfileNetworkBinding
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
            self.profile = profile
            self.attemptBinding = attemptBinding
            self.selectedInputs = selectedInputs
            self.outputAmountsSatoshis = outputAmountsSatoshis
            self.contributionPolicy = contributionPolicy
            self.transactionPolicy = transactionPolicy
            self.attemptJournal = attemptJournal
            self.currentDate = currentDate
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

        func persist(
            _ record: MosaicAttemptJournal.Record
        ) async throws {
            do {
                try await attemptJournal.append(record)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw MosaicHostFailure.journalPersistenceFailed
            }
        }
    }
}
#endif
