// CashCodePrefixGrindingEngine.swift

enum CashCodePrefixGrindingEngine {
    static func grind(
        maximumAttempts: Int,
        makeCandidate: @Sendable (Int) async throws -> OpalBase.Transaction,
        validateCandidate: @Sendable (OpalBase.Transaction) throws -> Bool
    ) async throws -> OpalBase.Transaction {
        guard maximumAttempts > 0,
              maximumAttempts <= OpalBase.ReusablePaymentAddress
                .CashCodeSpendPlan.defaultMaximumGrindingAttempts
        else {
            throw OpalBase.ReusablePaymentAddress.Error
                .invalidPrefixGrindingAttemptLimit
        }

        for attempt in 0..<maximumAttempts {
            try Task.checkCancellation()
            if attempt > 0, attempt.isMultiple(of: 256) {
                await Task.yield()
                try Task.checkCancellation()
            }
            let candidate = try await makeCandidate(attempt)
            try Task.checkCancellation()
            if try validateCandidate(candidate) {
                return candidate
            }
        }

        throw OpalBase.ReusablePaymentAddress.Error
            .prefixGrindingExhausted(attempts: maximumAttempts)
    }
}
