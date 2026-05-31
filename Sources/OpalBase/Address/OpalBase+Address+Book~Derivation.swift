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
        
        for usage in [OpalBase.Key.DerivationPath.Usage.receiving, .change] {
            let usageExtendedPrivateKey = try accountExtendedPrivateKey.derived(indices: [
                usage.unhardenedIndex
            ])
            let usageCompressedPublicKey = usageExtendedPrivateKey.publicKey.publicKey.rawRepresentation
            let usageFingerprint = OpalCryptoAdapter.fingerprint(of: usageCompressedPublicKey)
            usageDerivationCache[usage] = .init(baseExtendedPrivateKey: usageExtendedPrivateKey,
                                                baseCompressedPublicKey: usageCompressedPublicKey,
                                                baseFingerprint: usageFingerprint)
        }
    }
    
    func createDerivationPath(usage: OpalBase.Key.DerivationPath.Usage,
                              index: UInt32) throws -> OpalBase.Key.DerivationPath {
        let derivationPath = try OpalBase.Key.DerivationPath(purpose: self.purpose,
                                                coinType: self.coinType,
                                                account: self.account,
                                                usage: usage,
                                                index: index)
        return derivationPath
    }
    
    func generateAddress(at index: UInt32, for usage: OpalBase.Key.DerivationPath.Usage) throws -> OpalBase.Address {
        let derivationPath = try createDerivationPath(usage: usage, index: index)

        if let cachedUsageDerivation = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try cachedUsageDerivation.baseExtendedPrivateKey.derived(indices: [index])
            let childCompressedPublicKey = childExtendedPrivateKey.publicKey.publicKey.rawRepresentation
            return try makeAddress(fromCompressedPublicKey: childCompressedPublicKey)
        }

        let derivedPublicKey: OpalCrypto.Key.ExtendedPublic
        if let extendedPrivateKey = rootExtendedPrivateKey {
            derivedPublicKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).publicKey
        } else {
            derivedPublicKey = try rootExtendedPublicKey.derived(indices: derivationPath.makeIndices())
        }
        
        return try makeAddress(fromCompressedPublicKey: derivedPublicKey.publicKey.rawRepresentation)
    }
    
    func generatePrivateKey(at index: UInt32, for usage: OpalBase.Key.DerivationPath.Usage) throws -> Data {
        let derivationPath = try createDerivationPath(usage: usage, index: index)

        if let cachedUsageDerivation = usageDerivationCache[usage] {
            return try cachedUsageDerivation.baseExtendedPrivateKey.derived(indices: [index]).privateKey.rawRepresentation
        }

        guard let extendedPrivateKey = rootExtendedPrivateKey else { throw Error.privateKeyNotFound }
        let privateKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).privateKey
        
        return privateKey.rawRepresentation
    }

    func makeAddress(fromCompressedPublicKey compressedPublicKey: Data) throws -> OpalBase.Address {
        let publicKey = try OpalBase.Key.PublicKey(compressedData: compressedPublicKey)
        return try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
    }
}
