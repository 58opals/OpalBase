#if os(macOS)
// AccountCashFusionReservationValidator.swift

import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion preparation", .tags(.unit, .wallet))
struct AccountCashFusionReservationValidator {
    @Test("empty selected inputs are rejected")
    func emptySelectedInputsAreRejected() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [],
            outputAmounts: [try OpalBase.Satoshi(20_000)]
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionHasNoSelectedInputs) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }
    }

    @Test("empty output amounts are rejected")
    func emptyOutputAmountsAreRejected() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xB1
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [selectedInput],
            outputAmounts: []
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionHasNoOutputAmounts) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }
    }

    @Test("zero output amounts are rejected")
    func zeroOutputAmountsAreRejected() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xBC
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [selectedInput],
            outputAmounts: [OpalBase.Satoshi()]
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionHasNoOutputAmounts) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }
    }

    @Test("duplicate selected inputs are rejected before reservation")
    func duplicateSelectedInputsAreRejectedBeforeReservation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xBD
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [selectedInput, selectedInput],
            outputAmounts: [try OpalBase.Satoshi(25_000)]
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionUnsupportedSelectedInputs) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }

        let addressBook = await account.addressBook
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput))
    }

    @Test("token UTXOs are rejected")
    func tokenUTXOsAreRejected() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let tokenInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: CashFusionTestSupport.makeTokenData(),
            usage: .change,
            hashByte: 0xB2
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [tokenInput],
            outputAmounts: [try OpalBase.Satoshi(25_000)]
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionCannotSpendTokenUTXOs) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }
    }

    @Test("non-wallet-owned inputs are rejected")
    func nonWalletOwnedInputsAreRejected() async throws {
        let account = try await AccountTestFixtures.makeAccount(unhardenedIndex: 0)
        let foreignAccount = try await AccountTestFixtures.makeAccount(unhardenedIndex: 1)
        let foreignInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: foreignAccount,
            value: 90_000,
            usage: .change,
            hashByte: 0xB3
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [foreignInput],
            outputAmounts: [try OpalBase.Satoshi(22_000)]
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionUnsupportedSelectedInputs) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }
    }

    @Test("non-P2PKH selected inputs are rejected")
    func nonP2PKHSelectedInputsAreRejected() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xB4
        )
        let unsupportedInput = OpalBase.Transaction.Output.Unspent(
            value: selectedInput.value,
            lockingScript: Data([0x51]),
            tokenData: selectedInput.tokenData,
            previousTransactionHash: selectedInput.previousTransactionHash,
            previousTransactionOutputIndex: selectedInput.previousTransactionOutputIndex
        )
        let request = OpalBase.Account.CashFusionRequest(
            selectedInputs: [unsupportedInput],
            outputAmounts: [try OpalBase.Satoshi(25_000)]
        )

        await #expect(throws: OpalBase.Account.Error.cashFusionUnsupportedSelectedInputs) {
            _ = try await account.prepareCashFusionReservation(request: request)
        }
    }

    @Test("reserved receiving outputs use fresh wallet-owned receiving entries")
    func reservedReceivingOutputsUseFreshWalletOwnedReceivingEntries() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 200_000,
            usage: .change,
            hashByte: 0xB5
        )
        let expectedEntries = Array(
            await account.listEntries(for: .receiving).prefix(2)
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [selectedInput],
                outputAmounts: [
                    try OpalBase.Satoshi(40_000),
                    try OpalBase.Satoshi(50_000)
                ]
            )
        )

        #expect(reservation.reservedReceivingEntries.map(\.address) == expectedEntries.map(\.address))
        #expect(reservation.reservedReceivingEntries.allSatisfy { $0.derivationPath.usage == .receiving })
        #expect(reservation.reservedReceivingEntries.allSatisfy { $0.isReserved })
        let participantReservation = try await reservation.participantReservation(
            for: .init(rawValue: "round-explicit-outputs")
        )

        #expect(participantReservation.outputs.map(\.amountSatoshis) == [40_000, 50_000])
        #expect(participantReservation.outputs.map(\.lockingScriptBytes) == expectedEntries.map {
            [UInt8]($0.address.lockingScript.data)
        })

        try await reservation.cancel()
    }

    @Test("value-preserving outputs target the midpoint excess-fee range")
    func valuePreservingOutputsTargetMidpointExcessFeeRange() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 150_000,
            usage: .change,
            hashByte: 0xBE
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [selectedInput],
                outputPolicy: .valuePreserving
            )
        )
        let context = makeReservationContext(
            roundIdentifier: "round-value-preserving",
            numberOfComponents: 2,
            componentFeeRateSatoshisPerKb: 1_000,
            minimumExcessFeeSatoshis: 200,
            maximumExcessFeeSatoshis: 500
        )

        let participantReservation = try await reservation.participantReservation(for: context)
        let roundReservation = try await reservation.roundReservation(for: context.roundIdentifier)
        let output = try #require(participantReservation.outputs.first)
        let receivingEntry = try #require(roundReservation.reservedReceivingEntries.first)

        #expect(participantReservation.inputs.map(\.amountSatoshis) == [150_000])
        #expect(participantReservation.outputs.count == 1)
        #expect(output.amountSatoshis == 149_475)
        #expect(output.lockingScriptBytes == [UInt8](receivingEntry.address.lockingScript.data))
        #expect(roundReservation.participantReservation == participantReservation)

        try await reservation.cancel()
    }

    @Test("value-preserving reservations reject component-count overflow")
    func valuePreservingReservationsRejectComponentCountOverflow() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 150_000,
            usage: .change,
            hashByte: 0xBF
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [selectedInput],
                outputPolicy: .valuePreserving
            )
        )
        let context = makeReservationContext(
            roundIdentifier: "round-component-overflow",
            numberOfComponents: 1
        )

        await #expect(
            throws: OpalBase.Account.CashFusionRoundReservationError.componentCountLimitExceeded(
                required: 2,
                limit: 1
            )
        ) {
            _ = try await reservation.participantReservation(for: context)
        }
        await #expect(
            throws: OpalBase.Account.CashFusionRoundReservationError.missingRoundReservation(
                context.roundIdentifier
            )
        ) {
            _ = try await reservation.roundReservation(for: context.roundIdentifier)
        }

        try await reservation.cancel()
    }

    @Test("derived compressed public keys are attached to participant inputs")
    func derivedCompressedPublicKeysAreAttachedToParticipantInputs() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 110_000,
            usage: .change,
            hashByte: 0xB6
        )
        let secondInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 115_000,
            usage: .change,
            hashByte: 0xB7
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [firstInput, secondInput],
                outputAmounts: [try OpalBase.Satoshi(45_000)]
            )
        )

        let participantReservation = try await reservation.participantReservation(
            for: .init(rawValue: "round-derived-keys")
        )

        #expect(reservation.selectedInputs == [firstInput, secondInput])
        #expect(participantReservation.inputs.map(\.amountSatoshis) == [110_000, 115_000])

        for reservedInput in reservation.reservedInputs {
            #expect(reservedInput.participantInput.publicKey == [UInt8](reservedInput.compressedPublicKey))
            #expect(reservedInput.participantInput.lockingScriptBytes == [UInt8](reservedInput.unspentOutput.lockingScript))
            #expect(reservedInput.participantInput.outpointTransactionHashBytes == [UInt8](reservedInput.unspentOutput.previousTransactionHash.reverseOrder))
        }

        try await reservation.cancel()
    }

}

private extension AccountCashFusionReservationValidator {
    func makeReservationContext(
        roundIdentifier: String,
        numberOfComponents: UInt32,
        componentFeeRateSatoshisPerKb: UInt64 = 1_000,
        minimumExcessFeeSatoshis: UInt64 = 200,
        maximumExcessFeeSatoshis: UInt64 = 500
    ) -> OpalFusion.Host.ParticipantReservationContext {
        .init(
            roundIdentifier: .init(rawValue: roundIdentifier),
            tierSatoshis: 100_000,
            numberOfComponents: numberOfComponents,
            componentFeeRateSatoshisPerKb: componentFeeRateSatoshisPerKb,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis
        )
    }
}
#endif
