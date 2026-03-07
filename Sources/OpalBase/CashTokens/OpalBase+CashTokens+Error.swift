// OpalBase.CashTokens+Error.swift

import Foundation

extension _OpalBase.CashTokens {
    public enum Error: Swift.Error, Equatable {
        case invalidHexadecimalString
        case categoryIdentifierLengthMismatch(expected: Int, actual: Int)
        case commitmentLengthOutOfRange(minimum: Int, maximum: Int, actual: Int)
        case invalidFungibleAmountString(String)
        case invalidTokenPrefix
        case invalidTokenPrefixLength(expectedMinimum: Int, actual: Int)
        case invalidTokenPrefixBitfield
        case invalidTokenPrefixCompactSize
        case invalidTokenPrefixCommitmentLength
        case invalidTokenPrefixFungibleAmount
        case invalidTokenPrefixCapability
    }
}
