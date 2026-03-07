// AddressModel+BookActor~Derivation.swift

import Foundation

extension AddressModel.BookActor {
    func buildUsageDerivationCacheIfNeeded() throws {
        guard let rootExtendedPrivateKey else { return }
        
        let accountIndex = try account.deriveHardenedIndex()
        let accountExtendedPrivateKey = try rootExtendedPrivateKey.deriveChildFast(at: [
            purpose.hardenedIndex,
            coinType.hardenedIndex,
            accountIndex
        ])
        let accountCompressedPublicKey = try PublicKeyModel(privateKey: .init(data: accountExtendedPrivateKey.privateKey)).compressedData
        let accountFingerprint = Data(HASH160Model.hash(accountCompressedPublicKey).prefix(4))
        
        for usage in [DerivationPathModel.UsageModel.receiving, .change] {
            let usageExtendedPrivateKey = try accountExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: usage.unhardenedIndex,
                parentCompressedPublicKey: accountCompressedPublicKey,
                parentFingerprint: accountFingerprint
            )
            let usageCompressedPublicKey = try PublicKeyModel(privateKey: .init(data: usageExtendedPrivateKey.privateKey)).compressedData
            let usageFingerprint = Data(HASH160Model.hash(usageCompressedPublicKey).prefix(4))
            usageDerivationCache[usage] = .init(baseExtendedPrivateKey: usageExtendedPrivateKey,
                                                baseCompressedPublicKey: usageCompressedPublicKey,
                                                baseFingerprint: usageFingerprint)
        }
    }
    
    func createDerivationPath(usage: DerivationPathModel.UsageModel,
                              index: UInt32) throws -> DerivationPathModel {
        let derivationPath = try DerivationPathModel(purpose: self.purpose,
                                                coinType: self.coinType,
                                                account: self.account,
                                                usage: usage,
                                                index: index)
        return derivationPath
    }
    
    func generateAddress(at index: UInt32, for usage: DerivationPathModel.UsageModel) throws -> AddressModel {
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            let childCompressedPublicKey = try PublicKeyModel(privateKey: .init(data: childExtendedPrivateKey.privateKey)).compressedData
            let publicKey = try PublicKeyModel(compressedData: childCompressedPublicKey)
            return try AddressModel(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        let derivedPublicKey: PublicKeyModel.ExtendedModel
        if let extendedPrivateKey = rootExtendedPrivateKey {
            derivedPublicKey = try extendedPrivateKey.deriveChildPublicKey(at: derivationPath)
        } else {
            derivedPublicKey = try rootExtendedPublicKey.deriveChild(at: derivationPath)
        }
        
        let publicKey = try PublicKeyModel(compressedData: derivedPublicKey.publicKey)
        let address = try AddressModel(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        
        return address
    }
    
    func generatePrivateKey(at index: UInt32, for usage: DerivationPathModel.UsageModel) throws -> PrivateKeyModel {
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            return try PrivateKeyModel(data: childExtendedPrivateKey.privateKey)
        }
        
        guard let extendedPrivateKey = rootExtendedPrivateKey else { throw Error.privateKeyNotFound }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        let privateKey = try PrivateKeyModel(data: extendedPrivateKey.deriveChild(at: derivationPath).privateKey)
        
        return privateKey
    }
}
