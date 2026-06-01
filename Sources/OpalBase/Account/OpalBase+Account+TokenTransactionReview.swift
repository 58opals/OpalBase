// OpalBase+Account+TokenTransactionReview.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenOutputReview: Sendable, Equatable {
        public enum Role: Sendable, Equatable {
            case recipient
            case tokenChange
            case minted
        }
        
        public let role: Role
        public let value: OpalBase.Satoshi
        public let lockingScript: Data
        public let tokenData: OpalBase.CashTokens.TokenData?
        
        public var category: OpalBase.CashTokens.CategoryID? {
            tokenData?.category
        }
        
        public var fungibleAmount: UInt64? {
            tokenData?.amount
        }
        
        public var nonFungibleTokenCapability: OpalBase.CashTokens.NFT.Capability? {
            tokenData?.nft?.capability
        }
        
        public var nonFungibleTokenCommitment: Data? {
            tokenData?.nft?.commitment
        }
        
        public init(role: Role,
                    value: OpalBase.Satoshi,
                    lockingScript: Data,
                    tokenData: OpalBase.CashTokens.TokenData?) {
            self.role = role
            self.value = value
            self.lockingScript = Data(lockingScript)
            self.tokenData = tokenData
        }
    }
}

extension _OpalBase.Account.TokenOutputReview {
    init(output: OpalBase.Transaction.Output, role: Role) throws {
        try self.init(role: role,
                      value: OpalBase.Satoshi(output.value),
                      lockingScript: output.lockingScript,
                      tokenData: output.tokenData)
    }
}

extension _OpalBase.Account.TokenSpendPlan {
    public struct Review: Sendable {
        public let transaction: OpalBase.Transaction
        public let rawTransactionData: Data
        public let rawTransactionByteCount: Int
        public let fee: OpalBase.Satoshi
        public let configuredFeeRate: UInt64
        public let effectiveFeeRate: Double?
        public let bchChange: TransactionResult.Change?
        public let tokenRecipientOutputs: [OpalBase.Account.TokenOutputReview]
        public let tokenChangeOutputs: [OpalBase.Account.TokenOutputReview]
        public let lockedBCHOutputValue: OpalBase.Satoshi
        
        public init(transaction: OpalBase.Transaction,
                    rawTransactionData: Data,
                    rawTransactionByteCount: Int,
                    fee: OpalBase.Satoshi,
                    configuredFeeRate: UInt64,
                    effectiveFeeRate: Double?,
                    bchChange: TransactionResult.Change?,
                    tokenRecipientOutputs: [OpalBase.Account.TokenOutputReview],
                    tokenChangeOutputs: [OpalBase.Account.TokenOutputReview],
                    lockedBCHOutputValue: OpalBase.Satoshi) {
            self.transaction = transaction
            self.rawTransactionData = Data(rawTransactionData)
            self.rawTransactionByteCount = rawTransactionByteCount
            self.fee = fee
            self.configuredFeeRate = configuredFeeRate
            self.effectiveFeeRate = effectiveFeeRate
            self.bchChange = bchChange
            self.tokenRecipientOutputs = tokenRecipientOutputs
            self.tokenChangeOutputs = tokenChangeOutputs
            self.lockedBCHOutputValue = lockedBCHOutputValue
        }
    }
    
    public func buildReview(signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) throws -> Review {
        let result = try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers)
        let rawTransactionData = try result.transaction.encode()
        let rawTransactionByteCount = rawTransactionData.count
        var resolver = OpalBase.Transaction.Output.Resolver(outputs: result.transaction.outputs)
        let resolvedRecipientOutputs = try resolver.resolve(tokenRecipientOutputs).map {
            try OpalBase.Account.TokenOutputReview(output: $0, role: .recipient)
        }
        let resolvedTokenChangeOutputs = try resolver.resolve(tokenChangeOutputs).map {
            try OpalBase.Account.TokenOutputReview(output: $0, role: .tokenChange)
        }
        let lockedBCHOutputValue = try TokenTransactionReview.sumTokenOutputValue(
            resolvedRecipientOutputs + resolvedTokenChangeOutputs
        )
        
        return Review(transaction: result.transaction,
                      rawTransactionData: rawTransactionData,
                      rawTransactionByteCount: rawTransactionByteCount,
                      fee: result.fee,
                      configuredFeeRate: feeRate,
                      effectiveFeeRate: TokenTransactionReview.effectiveFeeRate(fee: result.fee,
                                                                                byteCount: rawTransactionByteCount),
                      bchChange: result.bchChange,
                      tokenRecipientOutputs: resolvedRecipientOutputs,
                      tokenChangeOutputs: resolvedTokenChangeOutputs,
                      lockedBCHOutputValue: lockedBCHOutputValue)
    }
}

extension _OpalBase.Account.TokenGenesisPlan {
    public struct Review: Sendable {
        public let transaction: OpalBase.Transaction
        public let rawTransactionData: Data
        public let rawTransactionByteCount: Int
        public let fee: OpalBase.Satoshi
        public let configuredFeeRate: UInt64
        public let effectiveFeeRate: Double?
        public let category: OpalBase.CashTokens.CategoryID
        public let mintedOutputs: [OpalBase.Account.TokenOutputReview]
        public let bchChange: OpalBase.Account.SpendPlan.TransactionResult.Change?
        public let lockedBCHOutputValue: OpalBase.Satoshi
        public let totalBCHNeeded: OpalBase.Satoshi
        
        public init(transaction: OpalBase.Transaction,
                    rawTransactionData: Data,
                    rawTransactionByteCount: Int,
                    fee: OpalBase.Satoshi,
                    configuredFeeRate: UInt64,
                    effectiveFeeRate: Double?,
                    category: OpalBase.CashTokens.CategoryID,
                    mintedOutputs: [OpalBase.Account.TokenOutputReview],
                    bchChange: OpalBase.Account.SpendPlan.TransactionResult.Change?,
                    lockedBCHOutputValue: OpalBase.Satoshi,
                    totalBCHNeeded: OpalBase.Satoshi) {
            self.transaction = transaction
            self.rawTransactionData = Data(rawTransactionData)
            self.rawTransactionByteCount = rawTransactionByteCount
            self.fee = fee
            self.configuredFeeRate = configuredFeeRate
            self.effectiveFeeRate = effectiveFeeRate
            self.category = category
            self.mintedOutputs = mintedOutputs
            self.bchChange = bchChange
            self.lockedBCHOutputValue = lockedBCHOutputValue
            self.totalBCHNeeded = totalBCHNeeded
        }
    }
    
    public func buildReview(signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) throws -> Review {
        let result = try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers)
        let rawTransactionData = try result.transaction.encode()
        let rawTransactionByteCount = rawTransactionData.count
        let mintedOutputs = try result.mintedOutputs.map {
            try OpalBase.Account.TokenOutputReview(output: $0, role: .minted)
        }
        let lockedBCHOutputValue = try TokenTransactionReview.sumTokenOutputValue(mintedOutputs)
        let totalBCHNeeded = try lockedBCHOutputValue + result.fee
        
        return Review(transaction: result.transaction,
                      rawTransactionData: rawTransactionData,
                      rawTransactionByteCount: rawTransactionByteCount,
                      fee: result.fee,
                      configuredFeeRate: feeRate,
                      effectiveFeeRate: TokenTransactionReview.effectiveFeeRate(fee: result.fee,
                                                                                byteCount: rawTransactionByteCount),
                      category: result.category,
                      mintedOutputs: mintedOutputs,
                      bchChange: result.bchChange,
                      lockedBCHOutputValue: lockedBCHOutputValue,
                      totalBCHNeeded: totalBCHNeeded)
    }
}
