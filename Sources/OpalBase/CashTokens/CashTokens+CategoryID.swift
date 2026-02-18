// CashTokens+CategoryID.swift

import Foundation

extension CashTokens {
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
            let rawData: Data
            do {
                rawData = try Data(hexadecimalString: hexadecimalString)
            } catch {
                throw Error.invalidHexadecimalString
            }
            let transactionOrderData = rawData.reversedData
            try self.init(transactionOrderData: transactionOrderData)
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
