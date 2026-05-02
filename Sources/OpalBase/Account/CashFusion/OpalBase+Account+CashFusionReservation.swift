#if os(macOS)
// OpalBase+Account+CashFusionReservation.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionReservation: Sendable {
        struct ReservedInput: Sendable {
            let unspentOutput: OpalBase.Transaction.Output.Unspent
            let privateKey: Data
            let compressedPublicKey: Data
            let participantInput: OpalFusion.Host.ParticipantInput
        }

        let addressBook: OpalBase.Address.Book
        let reservedInputs: [ReservedInput]
        let reservedReceivingEntries: [OpalBase.Address.Book.Entry]
        let participantReservation: OpalFusion.Host.ParticipantReservation

        var selectedInputs: [OpalBase.Transaction.Output.Unspent] {
            reservedInputs.map(\.unspentOutput)
        }

        func complete() async throws {
            try await releaseReservations(inputOutcome: .spent, shouldKeepUsed: true)
        }

        func cancel() async throws {
            try await releaseReservations(inputOutcome: .released, shouldKeepUsed: false)
        }

        private func releaseReservations(
            inputOutcome: InputOutcome,
            shouldKeepUsed: Bool
        ) async throws {
            switch inputOutcome {
            case .spent:
                for selectedInput in selectedInputs {
                    await addressBook.removeUTXO(selectedInput)
                }
            case .released:
                await addressBook.releaseUTXOs(Set(selectedInputs))
            }

            var firstError: Swift.Error?
            for entry in reservedReceivingEntries {
                do {
                    _ = try await addressBook.releaseReservation(
                        address: entry.address,
                        shouldKeepUsed: shouldKeepUsed
                    )
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if let firstError {
                throw firstError
            }
        }

        private enum InputOutcome {
            case spent
            case released
        }
    }
}
#endif
