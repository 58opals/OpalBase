// CashTokensFungibleAmountFormatStyleValidator.swift

import Testing
@testable import OpalBase

@Suite("CashTokens fungible amount format style", .tags(.unit, .cashTokens))
struct CashTokensFungibleAmountFormatStyleValidator {
    @Test("formats raw amounts", arguments: rawAmountFormatCases)
    fileprivate func formatsRawAmounts(_ formatCase: RawAmountFormatCase) {
        #expect(formatCase.value.formatted(.fungibleTokenAmount(decimals: formatCase.decimals)) == formatCase.expected)
    }

    @Test("clamps oversized decimal metadata")
    func clampsOversizedDecimalMetadata() {
        let formattedValue = UInt64(1).formatted(.fungibleTokenAmount(decimals: .max))

        #expect(formattedValue == "0.\(String(repeating: "0", count: 63))1")
    }

    @Test("formats optional symbols", arguments: symbolFormatCases)
    fileprivate func formatsOptionalSymbols(_ formatCase: SymbolFormatCase) {
        #expect(1_234.formatted(.fungibleTokenAmount(decimals: 2, symbol: formatCase.symbol)) == formatCase.expected)
    }

    private static let rawAmountFormatCases = [
        RawAmountFormatCase(value: 1_234, decimals: 0, expected: "1234"),
        RawAmountFormatCase(value: 1, decimals: 2, expected: "0.01"),
        RawAmountFormatCase(value: 100, decimals: 2, expected: "1.00"),
        RawAmountFormatCase(value: 1_234, decimals: 2, expected: "12.34"),
        RawAmountFormatCase(value: UInt64.max, decimals: 8, expected: "184467440737.09551615")
    ]

    private static let symbolFormatCases = [
        SymbolFormatCase(symbol: "TOK", expected: "12.34 TOK"),
        SymbolFormatCase(symbol: "  TOK  ", expected: "12.34 TOK"),
        SymbolFormatCase(symbol: nil, expected: "12.34"),
        SymbolFormatCase(symbol: "   ", expected: "12.34")
    ]

    struct RawAmountFormatCase: Sendable {
        let value: UInt64
        let decimals: Int
        let expected: String
    }

    struct SymbolFormatCase: Sendable {
        let symbol: String?
        let expected: String
    }
}
