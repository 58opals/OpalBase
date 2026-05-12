// CashTokensFungibleAmountFormatStyleValidator.swift

import Testing
@testable import OpalBase

@Suite("CashTokens fungible amount format style", .tags(.unit, .cashTokens))
struct CashTokensFungibleAmountFormatStyleValidator {
    @Test("formats raw amounts with zero decimals")
    func formatsRawAmountsWithZeroDecimals() {
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 0)) == "1234")
    }

    @Test("formats raw amounts with fixed fractional decimals")
    func formatsRawAmountsWithFixedFractionalDecimals() {
        #expect(1.formatted(.fungibleTokenAmount(decimals: 2)) == "0.01")
        #expect(100.formatted(.fungibleTokenAmount(decimals: 2)) == "1.00")
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 2)) == "12.34")
    }

    @Test("formats large raw amounts exactly")
    func formatsLargeRawAmountsExactly() {
        #expect(UInt64.max.formatted(.fungibleTokenAmount(decimals: 8)) == "184467440737.09551615")
    }

    @Test("appends non-empty symbols")
    func appendsNonEmptySymbols() {
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 2, symbol: "TOK")) == "12.34 TOK")
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 2, symbol: "  TOK  ")) == "12.34 TOK")
    }

    @Test("omits nil and empty symbols")
    func omitsNilAndEmptySymbols() {
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 2, symbol: nil)) == "12.34")
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 2, symbol: "   ")) == "12.34")
    }
}
