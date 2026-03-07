// OpalBase+Address+Book+SnapshotModel+UTXO.swift

import Foundation

extension _OpalBase.Address.Book.SnapshotModel {
    public struct UTXO: Codable, Equatable, Hashable, Sendable {
        public let value: UInt64
        public let lockingScript: String
        public let tokenCategory: String?
        public let tokenAmount: UInt64?
        public let nftCapability: OpalBase.CashTokens.NFTModel.Capability?
        public let nftCommitment: String?
        public let transactionHash: String
        public let outputIndex: UInt32

        public init(value: UInt64,
                    lockingScript: String,
                    tokenCategory: String?,
                    tokenAmount: UInt64?,
                    nftCapability: OpalBase.CashTokens.NFTModel.Capability?,
                    nftCommitment: String?,
                    transactionHash: String,
                    outputIndex: UInt32) {
            self.value = value
            self.lockingScript = lockingScript
            self.tokenCategory = tokenCategory
            self.tokenAmount = tokenAmount
            self.nftCapability = nftCapability
            self.nftCommitment = nftCommitment
            self.transactionHash = transactionHash
            self.outputIndex = outputIndex
        }

        public init(value: UInt64,
                    lockingScript: String,
                    tokenData: OpalBase.CashTokens.TokenData?,
                    transactionHash: String,
                    outputIndex: UInt32) {
            let nftCommitment = tokenData?.nft?.commitment.hexadecimalString
            self.init(value: value,
                      lockingScript: lockingScript,
                      tokenCategory: tokenData?.category.hexForDisplay,
                      tokenAmount: tokenData?.amount,
                      nftCapability: tokenData?.nft?.capability,
                      nftCommitment: nftCommitment,
                      transactionHash: transactionHash,
                      outputIndex: outputIndex)
        }

        public func makeTokenData() throws -> OpalBase.CashTokens.TokenData? {
            guard let tokenCategory else {
                guard tokenAmount == nil, nftCapability == nil, nftCommitment == nil else {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: SnapshotTokenDataError.missingTokenCategory)
                }
                return nil
            }

            let category: OpalBase.CashTokens.CategoryIDModel
            do {
                category = try OpalBase.CashTokens.CategoryIDModel(hexFromRPC: tokenCategory)
            } catch {
                throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: error)
            }

            let nonFungibleToken: OpalBase.CashTokens.NFTModel?
            if nftCapability == nil && nftCommitment == nil {
                nonFungibleToken = nil
            } else {
                guard let nftCapability, let nftCommitment else {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                        reason: SnapshotTokenDataError.missingNonFungibleTokenComponents
                    )
                }
                let commitmentData: Data
                do {
                    commitmentData = try Data(hexadecimalString: nftCommitment)
                } catch {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: error)
                }
                do {
                    nonFungibleToken = try OpalBase.CashTokens.NFTModel(capability: nftCapability, commitment: commitmentData)
                } catch {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: error)
                }
            }

            return OpalBase.CashTokens.TokenData(category: category, amount: tokenAmount, nft: nonFungibleToken)
        }

        private enum SnapshotTokenDataError: Swift.Error {
            case missingTokenCategory
            case missingNonFungibleTokenComponents
        }
    }
}

