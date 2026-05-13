// OpalBase+CashTokens+CategoryID.swift

import Foundation

extension _OpalBase.CashTokens {
    public struct CategoryID: Codable, Hashable, Sendable {
        private static let expectedByteCount = 32
        
        public let transactionOrderData: Data
        
        public init(transactionOrderData: Data) throws {
            guard transactionOrderData.count == Self.expectedByteCount else {
                throw Error.categoryIdentifierLengthMismatch(expected: Self.expectedByteCount,
                                                             actual: transactionOrderData.count)
            }
            self.transactionOrderData = transactionOrderData
        }
        
        public init(hexFromRPC hexadecimalString: String) throws {
            guard !hexadecimalString.hasPrefix("0x"),
                  !hexadecimalString.hasPrefix("0X"),
                  let rawData = try? Data(hexadecimalString: hexadecimalString) else {
                throw Error.invalidHexadecimalString
            }
            try self.init(transactionOrderData: rawData.reversedData)
        }
        
        public var hexForDisplay: String {
            transactionOrderData.reversedData.hexadecimalString
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let hexadecimalString = try container.decode(String.self)
            try self.init(hexFromRPC: hexadecimalString)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(hexForDisplay)
        }
    }
}
