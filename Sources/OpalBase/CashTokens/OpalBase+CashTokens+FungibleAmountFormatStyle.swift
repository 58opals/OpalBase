// OpalBase+CashTokens+FungibleAmountFormatStyle.swift

import Foundation

extension _OpalBase.CashTokens {
    public struct FungibleAmountFormatStyle: FormatStyle, Sendable {
        public typealias FormatInput = UInt64
        public typealias FormatOutput = String
        private static let maximumDisplayDecimals = 64

        public let decimals: Int
        public let symbol: String?

        public init(decimals: Int?, symbol: String? = nil) {
            self.decimals = min(max(0, decimals ?? 0), Self.maximumDisplayDecimals)
            let trimmedSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.symbol = trimmedSymbol?.isEmpty == false ? trimmedSymbol : nil
        }

        public func format(_ value: UInt64) -> String {
            let rawValue = String(value)
            let scaledValue = makeScaledValue(from: rawValue)
            guard let symbol else { return scaledValue }
            return "\(scaledValue) \(symbol)"
        }

        private func makeScaledValue(from rawValue: String) -> String {
            guard decimals > 0 else { return rawValue }

            if rawValue.count <= decimals {
                let leadingZeros = String(repeating: "0", count: decimals - rawValue.count)
                return "0.\(leadingZeros)\(rawValue)"
            }

            let splitIndex = rawValue.index(rawValue.endIndex, offsetBy: -decimals)
            let whole = rawValue[..<splitIndex]
            let fraction = rawValue[splitIndex...]
            return "\(whole).\(fraction)"
        }
    }
}

public extension FormatStyle where Self == OpalBase.CashTokens.FungibleAmountFormatStyle {
    static func fungibleTokenAmount(decimals: Int?, symbol: String? = nil) -> Self {
        OpalBase.CashTokens.FungibleAmountFormatStyle(decimals: decimals, symbol: symbol)
    }
}
