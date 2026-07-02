// AccountCashFusionParticipantReservationSourceValidator.swift

#if os(macOS)
import Foundation
import OpalDiagnostics
@testable import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion participant reservation source", .tags(.unit, .wallet))
struct AccountCashFusionParticipantReservationSourceValidator {
    @Test("empty participant reservations throw no eligible inputs")
    func emptyParticipantReservationsThrowNoEligibleInputs() async throws {
        let source = try await makeSource(
            reservedInputs: [],
            outputStrategy: .explicit([])
        )

        let failure = try await captureParticipantReservationFailure {
            _ = try await source.reserveParticipant(
                for: OpalFusion.Round.Identifier(rawValue: "round-no-eligible-inputs")
            )
        }

        #expect(failure == .hostPolicyRejected(
            reason: .noEligibleInputs,
            summary: "No eligible CashFusion inputs are available."
        ))
        try assertOpalFusionDiagnostics(
            for: failure,
            expectedErrorCode: "participant_reservation_host_policy_rejected",
            expectedHostResponseClass: "participant_reservation_rejected",
            expectedReasonCode: "no_eligible_inputs"
        )
    }

    @Test(
        "direct reservation failures preserve safe diagnostics",
        arguments: DirectReservationFailureMappingCase.allCases
    )
    func directReservationFailuresPreserveSafeDiagnostics(
        _ failureCase: DirectReservationFailureMappingCase
    ) throws {
        let failure = OpalBase.Account.CashFusionParticipantReservationSource
            .participantReservationFailure(for: failureCase.sourceError)

        #expect(failure == failureCase.expectedFailure)
        try assertOpalFusionDiagnostics(
            for: failure,
            expectedErrorCode: failureCase.expectedErrorCode,
            expectedHostResponseClass: failureCase.expectedHostResponseClass,
            expectedReasonCode: failureCase.expectedReasonCode
        )
    }

    @Test("unknown reservation errors remain typed reservation unavailable")
    func unknownReservationErrorsRemainTypedReservationUnavailable() async throws {
        let selectedInput = OpalBase.Transaction.Output.Unspent(
            value: 120_000,
            lockingScript: Data([0x51]),
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x71, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let source = try await makeSource(
            reservedInputs: [
                .init(
                    unspentOutput: selectedInput,
                    privateKey: Data(repeating: 0x01, count: 32),
                    compressedPublicKey: Data(repeating: 0x02, count: 33),
                    participantInput: .init(
                        outpointTransactionHashBytes: [UInt8](selectedInput.previousTransactionHash.reverseOrder),
                        outpointIndex: selectedInput.previousTransactionOutputIndex,
                        amountSatoshis: selectedInput.value,
                        lockingScriptBytes: [UInt8](selectedInput.lockingScript),
                        publicKey: [UInt8](Data(repeating: 0x02, count: 33))
                    )
                )
            ],
            outputStrategy: .valuePreserving
        )

        let failure = try await captureParticipantReservationFailure {
            _ = try await source.reserveParticipant(
                for: OpalFusion.Round.Identifier(rawValue: "round-missing-context")
            )
        }

        #expect(failure == .reservationUnavailable(
            reason: .unknown,
            summary: "CashFusion participant reservation is unavailable."
        ))
        try assertOpalFusionDiagnostics(
            for: failure,
            expectedErrorCode: "participant_reservation_unavailable",
            expectedHostResponseClass: "reservation_unavailable",
            expectedReasonCode: "unknown"
        )
    }

    private func makeSource(
        reservedInputs: [OpalBase.Account.CashFusionReservation.ReservedInput],
        outputStrategy: OpalBase.Account.CashFusionReservation.OutputStrategy
    ) async throws -> OpalBase.Account.CashFusionParticipantReservationSource {
        let account = try await AccountTestFixtures.makeAccount()
        return .init(
            reservation: .init(
                addressBook: await account.addressBook,
                reservedInputs: reservedInputs,
                reservedReceivingEntries: [],
                outputStrategy: outputStrategy
            )
        )
    }

    private func captureParticipantReservationFailure(
        _ operation: () async throws -> Void
    ) async throws -> OpalFusion.Host.ParticipantReservationFailure {
        do {
            try await operation()
        } catch let failure as OpalFusion.Host.ParticipantReservationFailure {
            return failure
        } catch {
            throw ParticipantReservationSourceCaptureFailure.unexpected(String(describing: error))
        }

        throw ParticipantReservationSourceCaptureFailure.didNotThrow
    }

    private func assertOpalFusionDiagnostics(
        for failure: OpalFusion.Host.ParticipantReservationFailure,
        expectedErrorCode: String,
        expectedHostResponseClass: String,
        expectedReasonCode: String
    ) throws {
        let fields = OpalDiagnostics.Field.hostFailureFields(for: failure)

        #expect(OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: failure).rawValue == expectedErrorCode)
        #expect(try requireField("host_response_class", in: fields).value == expectedHostResponseClass)
        #expect(try requireField("validation_branch", in: fields).value == "participant_reservation")
        #expect(try requireField("reason_code", in: fields).value == expectedReasonCode)
        assertFieldsOmitSensitiveFragments(fields)
    }

    private func requireField(
        _ name: String,
        in fields: [OpalDiagnostics.Field]
    ) throws -> OpalDiagnostics.Field {
        try #require(fields.first { $0.name == name })
    }

    private func assertFieldsOmitSensitiveFragments(
        _ fields: [OpalDiagnostics.Field]
    ) {
        let fieldValues = fields.map { $0.value.lowercased() }
        for forbiddenFragment in ["address", "key", "payload", "private", "transaction"] {
            #expect(
                fieldValues.contains { $0.contains(forbiddenFragment) } == false,
                "Diagnostics fields must not contain \(forbiddenFragment)"
            )
        }
    }

    enum DirectReservationFailureMappingCase: CaseIterable, Sendable, CustomStringConvertible {
        case unsupportedSelectedInputs
        case missingReservedInput
        case duplicatedReservedInput
        case alreadyReservedInput
        case walletKeyUnavailable
        case userCancelled

        var description: String {
            switch self {
            case .unsupportedSelectedInputs:
                "unsupportedSelectedInputs"
            case .missingReservedInput:
                "missingReservedInput"
            case .duplicatedReservedInput:
                "duplicatedReservedInput"
            case .alreadyReservedInput:
                "alreadyReservedInput"
            case .walletKeyUnavailable:
                "walletKeyUnavailable"
            case .userCancelled:
                "userCancelled"
            }
        }

        var sourceError: Swift.Error {
            switch self {
            case .unsupportedSelectedInputs:
                OpalBase.Account.Error.cashFusionUnsupportedSelectedInputs
            case .missingReservedInput:
                OpalBase.Account.Error.cashFusionReservationFailed(
                    OpalBase.Address.Book.Error.utxoNotFound
                )
            case .duplicatedReservedInput:
                OpalBase.Account.Error.cashFusionReservationFailed(
                    OpalBase.Address.Book.Error.utxoDuplicated(Self.reservedInputFixture)
                )
            case .alreadyReservedInput:
                OpalBase.Account.Error.cashFusionReservationFailed(
                    OpalBase.Address.Book.Error.utxoAlreadyReserved(Self.reservedInputFixture)
                )
            case .walletKeyUnavailable:
                OpalBase.Account.Error.cashFusionReservationFailed(
                    OpalBase.Address.Book.Error.privateKeyNotFound
                )
            case .userCancelled:
                CancellationError()
            }
        }

        var expectedFailure: OpalFusion.Host.ParticipantReservationFailure {
            switch self {
            case .unsupportedSelectedInputs:
                .hostPolicyRejected(
                    reason: .unsupportedInput,
                    summary: "CashFusion input selection is unsupported."
                )
            case .duplicatedReservedInput:
                .hostPolicyRejected(
                    reason: .unsupportedInput,
                    summary: "CashFusion input selection is unsupported."
                )
            case .missingReservedInput:
                .hostPolicyRejected(
                    reason: .noEligibleInputs,
                    summary: "No eligible CashFusion inputs are available."
                )
            case .alreadyReservedInput:
                .reservationUnavailable(
                    reason: .walletLocked,
                    summary: "CashFusion wallet signing context is unavailable."
                )
            case .walletKeyUnavailable:
                .reservationUnavailable(
                    reason: .walletLocked,
                    summary: "CashFusion wallet signing context is unavailable."
                )
            case .userCancelled:
                .reservationUnavailable(
                    reason: .userCancelled,
                    summary: "CashFusion participant reservation was cancelled."
                )
            }
        }

        var expectedErrorCode: String {
            switch self {
            case .unsupportedSelectedInputs, .missingReservedInput, .duplicatedReservedInput:
                "participant_reservation_host_policy_rejected"
            case .alreadyReservedInput, .walletKeyUnavailable, .userCancelled:
                "participant_reservation_unavailable"
            }
        }

        var expectedHostResponseClass: String {
            switch self {
            case .unsupportedSelectedInputs, .missingReservedInput, .duplicatedReservedInput:
                "participant_reservation_rejected"
            case .alreadyReservedInput, .walletKeyUnavailable, .userCancelled:
                "reservation_unavailable"
            }
        }

        var expectedReasonCode: String {
            switch self {
            case .unsupportedSelectedInputs, .duplicatedReservedInput:
                "unsupported_input"
            case .missingReservedInput:
                "no_eligible_inputs"
            case .alreadyReservedInput:
                "wallet_locked"
            case .walletKeyUnavailable:
                "wallet_locked"
            case .userCancelled:
                "user_cancelled"
            }
        }

        private static let reservedInputFixture = OpalBase.Transaction.Output.Unspent(
            value: 70_000,
            lockingScript: Data([0x51]),
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x72, count: 32)),
            previousTransactionOutputIndex: 0
        )
    }
}

private enum ParticipantReservationSourceCaptureFailure: Swift.Error {
    case didNotThrow
    case unexpected(String)
}
#endif
