// Address+Book~Derivation.swift

import Foundation

extension Address.Book {
    func buildUsageDerivationCacheIfNeeded() throws {
        guard let rootExtendedPrivateKey else { return }
        
        let accountIndex = try account.deriveHardenedIndex()
        let accountExtendedPrivateKey = try rootExtendedPrivateKey.deriveChildFast(at: [
            purpose.hardenedIndex,
            coinType.hardenedIndex,
            accountIndex
        ])
        let accountCompressedPublicKey = try PublicKey(privateKey: .init(data: accountExtendedPrivateKey.privateKey)).compressedData
        let accountFingerprint = Data(HASH160.hash(accountCompressedPublicKey).prefix(4))
        
        for usage in [DerivationPath.Usage.receiving, .change] {
            let usageExtendedPrivateKey = try accountExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: usage.unhardenedIndex,
                parentCompressedPublicKey: accountCompressedPublicKey,
                parentFingerprint: accountFingerprint
            )
            let usageCompressedPublicKey = try PublicKey(privateKey: .init(data: usageExtendedPrivateKey.privateKey)).compressedData
            let usageFingerprint = Data(HASH160.hash(usageCompressedPublicKey).prefix(4))
            usageDerivationCache[usage] = .init(baseExtendedPrivateKey: usageExtendedPrivateKey,
                                                baseCompressedPublicKey: usageCompressedPublicKey,
                                                baseFingerprint: usageFingerprint)
        }
    }
    
    func createDerivationPath(usage: DerivationPath.Usage,
                              index: UInt32) throws -> DerivationPath {
        let derivationPath = try DerivationPath(purpose: self.purpose,
                                                coinType: self.coinType,
                                                account: self.account,
                                                usage: usage,
                                                index: index)
        return derivationPath
    }
    
    func generateAddress(at index: UInt32, for usage: DerivationPath.Usage) throws -> Address {
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            let childCompressedPublicKey = try PublicKey(privateKey: .init(data: childExtendedPrivateKey.privateKey)).compressedData
            let publicKey = try PublicKey(compressedData: childCompressedPublicKey)
            return try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        let derivedPublicKey: PublicKey.Extended
        if let extendedPrivateKey = rootExtendedPrivateKey {
            derivedPublicKey = try extendedPrivateKey.deriveChildPublicKey(at: derivationPath)
        } else {
            derivedPublicKey = try rootExtendedPublicKey.deriveChild(at: derivationPath)
        }
        
        let publicKey = try PublicKey(compressedData: derivedPublicKey.publicKey)
        let address = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        
        return address
    }
    
    func generatePrivateKey(at index: UInt32, for usage: DerivationPath.Usage) throws -> PrivateKey {
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            return try PrivateKey(data: childExtendedPrivateKey.privateKey)
        }
        
        guard let extendedPrivateKey = rootExtendedPrivateKey else { throw Error.privateKeyNotFound }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        let privateKey = try PrivateKey(data: extendedPrivateKey.deriveChild(at: derivationPath).privateKey)
        
        return privateKey
    }
}
