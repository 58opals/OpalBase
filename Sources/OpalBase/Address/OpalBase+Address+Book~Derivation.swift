// OpalBase+Address+Book~Derivation.swift

import Foundation
import OpalCrypto

extension _OpalBase.Address.Book {
    func buildUsageDerivationCacheIfNeeded() throws {
        guard case .rootPrivate(let rootExtendedPrivateKey) = keyOrigin else { return }
        
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
        try OpalBase.Key.DerivationPath(purpose: self.purpose,
                                         coinType: self.coinType,
                                         account: self.account,
                                         usage: usage,
                                         index: index)
    }
    
    func generateAddress(at index: UInt32, for usage: OpalBase.Key.DerivationPath.Usage) throws -> OpalBase.Address {
        let derivationPath = try createDerivationPath(usage: usage, index: index)

        if let cachedUsageDerivation = usageDerivationCache[usage] {
            let childExtendedPrivateKey = try cachedUsageDerivation.baseExtendedPrivateKey.derived(indices: [index])
            let childCompressedPublicKey = childExtendedPrivateKey.publicKey.publicKey.rawRepresentation
            return try makeAddress(fromCompressedPublicKey: childCompressedPublicKey)
        }

        let derivedPublicKey: OpalCrypto.Key.ExtendedPublic
        switch keyOrigin {
        case .rootPrivate(let extendedPrivateKey):
            derivedPublicKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).publicKey
        case .accountPublic(let accountExtendedPublicKey):
            derivedPublicKey = try accountExtendedPublicKey.derived(indices: [
                usage.unhardenedIndex,
                index
            ])
        }
        
        return try makeAddress(fromCompressedPublicKey: derivedPublicKey.publicKey.rawRepresentation)
    }
    
    func generatePrivateKey(at index: UInt32, for usage: OpalBase.Key.DerivationPath.Usage) throws -> Data {
        let derivationPath = try createDerivationPath(usage: usage, index: index)

        if let cachedUsageDerivation = usageDerivationCache[usage] {
            return try cachedUsageDerivation.baseExtendedPrivateKey.derived(indices: [index]).privateKey.rawRepresentation
        }

        guard case .rootPrivate(let extendedPrivateKey) = keyOrigin else { throw Error.privateKeyNotFound }
        let privateKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).privateKey
        
        return privateKey.rawRepresentation
    }

    func generateSigningKey(at index: UInt32, for usage: OpalBase.Key.DerivationPath.Usage) throws -> OpalBase.Key.SigningKey {
        let derivationPath = try createDerivationPath(usage: usage, index: index)

        if let cachedUsageDerivation = usageDerivationCache[usage] {
            return try OpalBase.Key.SigningKey(
                opalCryptoSigningKey: cachedUsageDerivation.baseExtendedPrivateKey.derived(indices: [index]).signingKey
            )
        }

        guard case .rootPrivate(let extendedPrivateKey) = keyOrigin else { throw Error.privateKeyNotFound }
        let signingKey = try extendedPrivateKey.derived(indices: derivationPath.makeIndices()).signingKey
        return try OpalBase.Key.SigningKey(opalCryptoSigningKey: signingKey)
    }

    func makeAddress(fromCompressedPublicKey compressedPublicKey: Data) throws -> OpalBase.Address {
        let publicKey = try OpalBase.Key.PublicKey(compressedData: compressedPublicKey)
        return try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
    }
}
