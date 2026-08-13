// CashCodeSenderRealCryptoConformanceValidator.swift

import Testing
@testable import OpalBase

@Suite(
    "Cash Code sender real-crypto conformance",
    .tags(.integration, .cryptography, .wallet, .transaction)
)
struct CashCodeSenderRealCryptoConformanceValidator {
    @Test(
        "production random-nonce signing yields a valid hit or exact exhaustion",
        .timeLimit(.minutes(5))
    )
    func exerciseProductionRandomNonceSigning() async throws {
        let plan = try await CashCodeSenderValidator()
            .prepareBitcoinCashPlan(hashByte: 0x79)

        do {
            let transaction = try await plan.buildTransaction(
                maximumGrindingAttempts: 1
            )
            #expect(
                plan.address.filterPrefix.matches(
                    transaction.inputs[plan.qualifyingInputIndex]
                )
            )
            #expect(
                transaction.outputs.contains {
                    $0.value == plan.request.amount.uint64
                        && $0.lockingScript == plan.payment.lockingScript
                        && $0.tokenData == plan.request.tokenData
                }
            )
            try await plan.cancelReservation()
        } catch let error as OpalBase.ReusablePaymentAddress.Error {
            guard error == .prefixGrindingExhausted(attempts: 1) else {
                throw error
            }
        }
    }
}
