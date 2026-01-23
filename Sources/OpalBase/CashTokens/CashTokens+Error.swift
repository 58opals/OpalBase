// CashTokens+Error.swift

import Foundation

extension CashTokens {
    public enum Error: Swift.Error {
        case invalidHexadecimalString
        case categoryIdentifierLengthMismatch(expected: Int, actual: Int)
        case commitmentLengthOutOfRange(minimum: Int, maximum: Int, actual: Int)
        case invalidFungibleAmountString(String)
    }
}
