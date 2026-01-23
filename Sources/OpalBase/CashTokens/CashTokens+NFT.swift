// CashTokens+NFT.swift

import Foundation

extension CashTokens {
    public struct NFT: Codable, Hashable, Sendable {
        private static let commitmentByteCountRange = 0...40
        
        public enum Capability: String, Codable, Hashable, Sendable {
            case none
            case mutable
            case minting
        }
        
        public let capability: Capability
        public let commitment: Data
        
        public init(capability: Capability, commitment: Data) throws {
            guard Self.commitmentByteCountRange.contains(commitment.count) else {
                throw Error.commitmentLengthOutOfRange(minimum: Self.commitmentByteCountRange.lowerBound,
                                                       maximum: Self.commitmentByteCountRange.upperBound,
                                                       actual: commitment.count)
            }
            self.capability = capability
            self.commitment = commitment
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let capability = try container.decode(Capability.self, forKey: .capability)
            let commitmentString = try container.decode(String.self, forKey: .commitment)
            let commitment: Data
            do {
                commitment = try Data(hexadecimalString: commitmentString)
            } catch {
                throw Error.invalidHexadecimalString
            }
            try self.init(capability: capability, commitment: commitment)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(capability, forKey: .capability)
            try container.encode(commitment.hexadecimalString, forKey: .commitment)
        }
        
        private enum CodingKeys: String, CodingKey {
            case capability
            case commitment
        }
    }
}
