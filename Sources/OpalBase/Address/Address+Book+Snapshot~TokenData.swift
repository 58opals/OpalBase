// Address+Book+Snapshot~TokenData.swift

import Foundation

extension Address.Book.Snapshot {
    public struct UTXO: Codable, Equatable, Hashable, Sendable {
        public let value: UInt64
        public let lockingScript: String
        public let tokenCategory: String?
        public let tokenAmount: UInt64?
        public let nftCapability: CashTokens.NFT.Capability?
        public let nftCommitment: String?
        public let transactionHash: String
        public let outputIndex: UInt32

        public init(value: UInt64,
                    lockingScript: String,
                    tokenCategory: String?,
                    tokenAmount: UInt64?,
                    nftCapability: CashTokens.NFT.Capability?,
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
                    tokenData: CashTokens.TokenData?,
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

        public func makeTokenData() throws -> CashTokens.TokenData? {
            guard let tokenCategory else {
                guard tokenAmount == nil, nftCapability == nil, nftCommitment == nil else {
                    throw Address.Book.Error.invalidSnapshotTokenData(reason: SnapshotTokenDataError.missingTokenCategory)
                }
                return nil
            }

            let category: CashTokens.CategoryID
            do {
                category = try CashTokens.CategoryID(hexFromRPC: tokenCategory)
            } catch {
                throw Address.Book.Error.invalidSnapshotTokenData(reason: error)
            }

            let nonFungibleToken: CashTokens.NFT?
            if nftCapability == nil && nftCommitment == nil {
                nonFungibleToken = nil
            } else {
                guard let nftCapability, let nftCommitment else {
                    throw Address.Book.Error.invalidSnapshotTokenData(
                        reason: SnapshotTokenDataError.missingNonFungibleTokenComponents
                    )
                }
                let commitmentData: Data
                do {
                    commitmentData = try Data(hexadecimalString: nftCommitment)
                } catch {
                    throw Address.Book.Error.invalidSnapshotTokenData(reason: error)
                }
                do {
                    nonFungibleToken = try CashTokens.NFT(capability: nftCapability, commitment: commitmentData)
                } catch {
                    throw Address.Book.Error.invalidSnapshotTokenData(reason: error)
                }
            }

            return CashTokens.TokenData(category: category, amount: tokenAmount, nft: nonFungibleToken)
        }

        private enum SnapshotTokenDataError: Swift.Error {
            case missingTokenCategory
            case missingNonFungibleTokenComponents
        }
    }
}
