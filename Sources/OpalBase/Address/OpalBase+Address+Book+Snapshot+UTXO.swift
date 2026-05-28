// OpalBase+Address+Book+Snapshot+UTXO.swift

import Foundation

extension _OpalBase.Address.Book.Snapshot {
    struct UTXO: Codable, Equatable, Hashable, Sendable {
        let value: UInt64
        let lockingScript: String
        let tokenCategory: String?
        let tokenAmount: UInt64?
        let nftCapability: OpalBase.CashTokens.NFT.Capability?
        let nftCommitment: String?
        let transactionHash: String
        let outputIndex: UInt32

        init(value: UInt64,
                    lockingScript: String,
                    tokenCategory: String?,
                    tokenAmount: UInt64?,
                    nftCapability: OpalBase.CashTokens.NFT.Capability?,
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

        init(value: UInt64,
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

        func makeTokenData() throws -> OpalBase.CashTokens.TokenData? {
            guard let tokenCategory else {
                guard tokenAmount == nil, nftCapability == nil, nftCommitment == nil else {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: SnapshotTokenDataError.missingTokenCategory)
                }
                return nil
            }

            let category: OpalBase.CashTokens.CategoryID
            do {
                category = try OpalBase.CashTokens.CategoryID(hexFromRPC: tokenCategory)
            } catch {
                throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: error)
            }

            if let tokenAmount, tokenAmount == 0 {
                throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                    reason: OpalBase.CashTokens.Error.invalidTokenPrefixFungibleAmount
                )
            }

            let nonFungibleToken: OpalBase.CashTokens.NFT?
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
                    guard !nftCommitment.hasPrefix("0x"),
                          !nftCommitment.hasPrefix("0X")
                    else {
                        throw OpalBase.CashTokens.Error.invalidHexadecimalString
                    }
                    commitmentData = try Data(hexadecimalString: nftCommitment)
                } catch {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: error)
                }
                do {
                    nonFungibleToken = try OpalBase.CashTokens.NFT(capability: nftCapability, commitment: commitmentData)
                } catch {
                    throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(reason: error)
                }
            }

            guard tokenAmount != nil || nonFungibleToken != nil else {
                throw OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                    reason: OpalBase.CashTokens.Error.invalidTokenPrefix
                )
            }

            return OpalBase.CashTokens.TokenData(category: category, amount: tokenAmount, nft: nonFungibleToken)
        }

        private enum SnapshotTokenDataError: Swift.Error {
            case missingTokenCategory
            case missingNonFungibleTokenComponents
        }
    }
}
