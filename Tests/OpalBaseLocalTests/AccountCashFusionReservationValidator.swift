// AccountCashFusionReservationValidator.swift

import Foundation
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
        #expect(reservation.participantReservation.outputs.map(\.lockingScript) == expectedEntries.map {
            [UInt8]($0.address.lockingScript.data)
        })

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

        for reservedInput in reservation.reservedInputs {
            #expect(reservedInput.participantInput.publicKey == [UInt8](reservedInput.compressedPublicKey))
            #expect(reservedInput.participantInput.lockingScript == [UInt8](reservedInput.unspentOutput.lockingScript))
            #expect(reservedInput.participantInput.outpointTransactionHash == [UInt8](reservedInput.unspentOutput.previousTransactionHash.reverseOrder))
        }

        try await reservation.cancel()
    }
}
