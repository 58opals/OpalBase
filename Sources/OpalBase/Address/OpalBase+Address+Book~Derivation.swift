// OpalBase+Address+Book~Derivation.swift

import Foundation
import OpalCrypto

extension _OpalBase.Address.Book {
    func buildUsageDerivationCacheIfNeeded() throws {
        guard let rootExtendedPrivateKey else { return }
        
        let accountIndex = try account.deriveHardenedIndex()
        let accountExtendedPrivateKey = try rootExtendedPrivateKey.derived(indices: [
            purpose.hardenedIndex,
            coinType.hardenedIndex,
            accountIndex
        ])
        
        for usage in [OpalBase.DerivationPath.Usage.receiving, .change] {
            let usageExtendedPrivateKey = try accountExtendedPrivateKey.derived(indices: [
                usage.unhardenedIndex
            ])
            let usageCompressedPublicKey = usageExtendedPrivateKey.publicKey.publicKey
            let usageFingerprint = OpalCryptoAdapter.fingerprint(of: usageCompressedPublicKey)
            usageDerivationCache[usage] = .init(baseExtendedPrivateKey: usageExtendedPrivateKey,
                                                baseCompressedPublicKey: usageCompressedPublicKey,
                                                baseFingerprint: usageFingerprint)
        }
    }
    
    func createDerivationPath(usage: OpalBase.DerivationPath.Usage,
                              index: UInt32) throws -> OpalBase.DerivationPath {
        let derivationPath = try OpalBase.DerivationPath(purpose: self.purpose,
                                                coinType: self.coinType,
                                                account: self.account,
                                                usage: usage,
                                                index: index)
        return derivationPath
    }
    
    func generateAddress(at index: UInt32, for usage: OpalBase.DerivationPath.Usage) throws -> OpalBase.Address {
        if let usageCache = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.derived(indices: [index])
            let childCompressedPublicKey = childExtendedPrivateKey.publicKey.publicKey
            let publicKey = try OpalBase.PublicKey(compressedData: childCompressedPublicKey)
            return try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        let derivedPublicKey: OpalCrypto.Key.ExtendedPublicKey
        if let extendedPrivateKey = rootExtendedPrivateKey {
            derivedPublicKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).publicKey
        } else {
            derivedPublicKey = try rootExtendedPublicKey.derived(indices: derivationPath.makeIndices())
        }
        
        let publicKey = try OpalBase.PublicKey(compressedData: derivedPublicKey.publicKey)
        let address = try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        
        return address
    }
    
    func generatePrivateKey(at index: UInt32, for usage: OpalBase.DerivationPath.Usage) throws -> Data {
        if let usageCache = usageDerivationCache[usage] {
            return try usageCache.baseExtendedPrivateKey.derived(indices: [index]).privateKey
        }
        
        guard let extendedPrivateKey = rootExtendedPrivateKey else { throw Error.privateKeyNotFound }
        
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        let privateKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).privateKey
        
        return privateKey
    }
}
