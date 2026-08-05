// OpalBase+ReusablePaymentAddress+DerivationContext.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// Public Cash Code derivation inputs retained for capability rederivation.
    public struct DerivationContext: Codable, Hashable, Sendable {
        public let senderPublicKey: OpalBase.Key.PublicKey
        public let senderOutpoint: OpalBase.Transaction.Outpoint
        public let qualifyingInputIndex: UInt32
        public let childIndex: UInt32
        public let receivingPublicKey: OpalBase.Key.PublicKey

        init(match: Match) {
            self.senderPublicKey = match.senderPublicKey
            self.senderOutpoint = match.senderOutpoint
            self.qualifyingInputIndex = match.qualifyingInputIndex
            self.childIndex = match.childIndex
            self.receivingPublicKey = match.receivingPublicKey
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CashCodeDerivationContextCodingKey.self
            )
            do {
                senderPublicKey = try OpalBase.Key.PublicKey(
                    compressedData: container.decode(
                        Data.self,
                        forKey: .senderPublicKey
                    )
                )
                senderOutpoint = try container.decode(
                    OpalBase.Transaction.Outpoint.self,
                    forKey: .senderOutpoint
                )
                qualifyingInputIndex = try container.decode(
                    UInt32.self,
                    forKey: .qualifyingInputIndex
                )
                childIndex = try container.decode(
                    UInt32.self,
                    forKey: .childIndex
                )
                receivingPublicKey = try OpalBase.Key.PublicKey(
                    compressedData: container.decode(
                        Data.self,
                        forKey: .receivingPublicKey
                    )
                )
            } catch let error as DecodingError {
                throw error
            } catch {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription:
                            "Invalid Cash Code public derivation context."
                    )
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(
                keyedBy: CashCodeDerivationContextCodingKey.self
            )
            try container.encode(
                senderPublicKey.compressedData,
                forKey: .senderPublicKey
            )
            try container.encode(senderOutpoint, forKey: .senderOutpoint)
            try container.encode(
                qualifyingInputIndex,
                forKey: .qualifyingInputIndex
            )
            try container.encode(childIndex, forKey: .childIndex)
            try container.encode(
                receivingPublicKey.compressedData,
                forKey: .receivingPublicKey
            )
        }
    }
}
