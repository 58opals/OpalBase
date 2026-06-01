// TokenTransactionReview.swift

enum TokenTransactionReview {
    static func effectiveFeeRate(fee: OpalBase.Satoshi, byteCount: Int) -> Double? {
        guard byteCount > 0 else { return nil }
        return Double(fee.uint64) / Double(byteCount)
    }

    static func sumTokenOutputValue(_ outputs: [OpalBase.Account.TokenOutputReview]) throws -> OpalBase.Satoshi {
        try outputs.sumSatoshi(or: OpalBase.Account.Error.paymentExceedsMaximumAmount) { output in
            output.value
        }
    }
}
