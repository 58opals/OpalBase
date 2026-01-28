// CashTokens+TokenPrefix.swift

import Foundation

extension CashTokens {
    public enum TokenPrefix {
        public static let prefixToken: UInt8 = 0xEF
        private static let reservedBit: UInt8 = 0x80
        private static let hasCommitmentLengthBit: UInt8 = 0x40
        private static let hasNonFungibleTokenBit: UInt8 = 0x20
        private static let hasFungibleAmountBit: UInt8 = 0x10
        private static let nonFungibleCapabilityMask: UInt8 = 0x0F
        private static let minimumPrefixLength = 34
        private static let maximumFungibleAmount: UInt64 = 0x7fff_ffff_ffff_ffff
        private static let categoryIdentifierByteCount = 32
        
        public static func encode(tokenData: TokenData) throws -> Data {
            guard tokenData.amount != nil || tokenData.nft != nil else {
                throw Error.invalidTokenPrefix
            }
            
            var tokenBitfield: UInt8 = 0
            var nonFungibleTokenCommitment = Data()
            
            if let nonFungibleToken = tokenData.nft {
                tokenBitfield |= hasNonFungibleTokenBit
                tokenBitfield |= capabilityValue(from: nonFungibleToken.capability)
                if !nonFungibleToken.commitment.isEmpty {
                    tokenBitfield |= hasCommitmentLengthBit
                    nonFungibleTokenCommitment = nonFungibleToken.commitment
                }
            }
            
            if let amount = tokenData.amount {
                guard amount >= 1, amount <= maximumFungibleAmount else {
                    throw Error.invalidTokenPrefixFungibleAmount
                }
                tokenBitfield |= hasFungibleAmountBit
            }
            
            var writer = Data.Writer()
            writer.writeByte(prefixToken)
            writer.writeData(tokenData.category.transactionOrderData)
            writer.writeByte(tokenBitfield)
            
            if !nonFungibleTokenCommitment.isEmpty {
                writer.writeCompactSize(CompactSize(value: UInt64(nonFungibleTokenCommitment.count)))
                writer.writeData(nonFungibleTokenCommitment)
            }
            
            if let amount = tokenData.amount {
                writer.writeCompactSize(CompactSize(value: amount))
            }
            
            return writer.data
        }
        
        public static func decode(prefixPlusBytecode: Data) throws -> (tokenData: TokenData?, lockingBytecode: Data) {
            guard let prefixByte = prefixPlusBytecode.first, prefixByte == prefixToken else {
                return (nil, prefixPlusBytecode)
            }
            
            guard prefixPlusBytecode.count >= minimumPrefixLength else {
                throw Error.invalidTokenPrefixLength(expectedMinimum: minimumPrefixLength,
                                                     actual: prefixPlusBytecode.count)
            }
            
            var reader = Data.Reader(prefixPlusBytecode)
            try reader.advance(by: 1)
            let categoryData = try reader.readData(count: categoryIdentifierByteCount)
            let tokenBitfield = try readTokenBitfield(from: &reader)
            
            let hasCommitmentLength = tokenBitfield & hasCommitmentLengthBit != 0
            let hasNonFungibleToken = tokenBitfield & hasNonFungibleTokenBit != 0
            let hasFungibleAmount = tokenBitfield & hasFungibleAmountBit != 0
            let capabilityValue = tokenBitfield & nonFungibleCapabilityMask
            
            guard tokenBitfield & reservedBit == 0 else {
                throw Error.invalidTokenPrefixBitfield
            }
            
            guard hasNonFungibleToken || hasFungibleAmount else {
                throw Error.invalidTokenPrefixBitfield
            }
            
            guard !(hasCommitmentLength && !hasNonFungibleToken) else {
                throw Error.invalidTokenPrefixBitfield
            }
            
            var nonFungibleToken: NFT?
            if hasNonFungibleToken {
                let capability = try capability(from: capabilityValue)
                var commitment = Data()
                if hasCommitmentLength {
                    let commitmentLength = try readCanonicalCompactSize(from: &reader)
                    guard commitmentLength > 0 else {
                        throw Error.invalidTokenPrefixCommitmentLength
                    }
                    guard commitmentLength <= reader.remainingData.count else {
                        throw Error.invalidTokenPrefixCommitmentLength
                    }
                    commitment = try reader.readData(count: Int(commitmentLength))
                }
                nonFungibleToken = try NFT(capability: capability, commitment: commitment)
            } else {
                guard capabilityValue == 0 else {
                    throw Error.invalidTokenPrefixCapability
                }
            }
            
            var amount: UInt64?
            if hasFungibleAmount {
                let parsedAmount = try readCanonicalCompactSize(from: &reader)
                guard parsedAmount >= 1, parsedAmount <= maximumFungibleAmount else {
                    throw Error.invalidTokenPrefixFungibleAmount
                }
                amount = parsedAmount
            }
            
            let category = try CategoryID(transactionOrderData: categoryData)
            let tokenData = TokenData(category: category, amount: amount, nft: nonFungibleToken)
            return (tokenData, reader.remainingData)
        }
        
        private static func readTokenBitfield(from reader: inout Data.Reader) throws -> UInt8 {
            guard let tokenBitfield = reader.remainingData.first else {
                throw Error.invalidTokenPrefixLength(expectedMinimum: minimumPrefixLength,
                                                     actual: reader.bytesRead)
            }
            try reader.advance(by: 1)
            return tokenBitfield
        }
        
        private static func readCanonicalCompactSize(from reader: inout Data.Reader) throws -> UInt64 {
            let compactSize: CompactSize
            let bytesRead: Int
            do {
                (compactSize, bytesRead) = try CompactSize.decode(from: reader.remainingData)
            } catch {
                throw Error.invalidTokenPrefixCompactSize
            }
            
            let canonicalLength = CompactSize(value: compactSize.value).encode().count
            guard bytesRead == canonicalLength else {
                throw Error.invalidTokenPrefixCompactSize
            }
            try reader.advance(by: bytesRead)
            return compactSize.value
        }
        
        private static func capability(from value: UInt8) throws -> NFT.Capability {
            switch value {
            case 0:
                return .none
            case 1:
                return .mutable
            case 2:
                return .minting
            default:
                throw Error.invalidTokenPrefixCapability
            }
        }
        
        private static func capabilityValue(from capability: NFT.Capability) -> UInt8 {
            switch capability {
            case .none:
                return 0
            case .mutable:
                return 1
            case .minting:
                return 2
            }
        }
    }
}
