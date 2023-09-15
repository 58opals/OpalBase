// Opal Base by 58 Opals

import Foundation
import BigInt

struct ExtendedPrivateKey: PrivateKey, Extendable, CustomStringConvertible {
    typealias PublicKeyType = ExtendedPublicKey
    
    let algorithm: Cryptography.Algorithm
    let network: BitcoinCash.Network
    let data: Data
    
    let precedent: (key: Data, chainCode: Data, fingerprint: Data)?
    
    let chainCode: Data
    let depth: UInt8
    let index: UInt32
    
    init(from exsitingSeed: Data? = nil,
         key secretKey: Data,
         precedent: (key: Data, chainCode: Data, fingerprint: Data)?,
         depth: UInt8 = 0,
         index: UInt32 = 0,
         algorithm: Cryptography.Algorithm,
         network: BitcoinCash.Network = .mainnet) {
        
        self.algorithm = algorithm
        self.network = network
        
        self.precedent = precedent
        self.depth = depth
        self.index = index
        
        let seed = exsitingSeed ?? Data.generateSecuredRandomBytes(count: 64)
        let symmetricKey = Cryptography.pbkdf2.getSymmetryKey(from: secretKey)
        let extendedKey: Data = Cryptography.pbkdf2.getHMACSHA512(for: seed, sing: symmetricKey)
        let isRoot: Bool = (depth == 0)
        
        switch isRoot {
        case true: // Root Extended Private Key
            self.data = extendedKey[0..<32]
            self.chainCode = extendedKey[32..<64]
            
        case false: // Child Extended Private Key
            let precedentPrivateKeyInteger: BigUInt = .init(precedent!.key)
            let hashed32BytesInteger: BigUInt = .init(extendedKey[0..<32])
            let orderOfTheCurve: BigUInt = .init(Data([255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 186, 174, 220, 230, 175, 72, 160, 59, 191, 210, 94, 140, 208, 54, 65, 65]))
            
            var calculationResult = ((precedentPrivateKeyInteger + hashed32BytesInteger) % orderOfTheCurve).serialize()
            while calculationResult.count < 32 {
                calculationResult = Data([0]) + calculationResult
            }
            
            self.data = calculationResult
            self.chainCode = precedent!.chainCode
        }
    }
    
    var basicPrivateKey: BasicPrivateKey {
        BasicPrivateKey(data[0..<32],
                        using: self.algorithm,
                        on: self.network)
    }
    
    var extendedPublicKey: PublicKeyType {
        return Cryptography.k1.generatePublicKey(from: self)
    }
    
    var publicKey: ExtendedPublicKey {
        return self.extendedPublicKey
    }
    
    func createSignature(for message: Data) -> Data {
        return Cryptography.k1.sign(message: message, from: self.basicPrivateKey)
    }
    
    func diverge(to index: DerivationPath.Index, depth: UInt8) -> ExtendedPrivateKey {
        let seed: Data = (index.isHardened ? (Data([0]) + self.data) : self.publicKey.compressed) + index.number.data.reversed()
        let key: Data = self.chainCode
        
        let newSymmetricKey = Cryptography.pbkdf2.getSymmetryKey(from: self.chainCode)
        let newExtendedKey: Data = Cryptography.pbkdf2.getHMACSHA512(for: seed, sing: newSymmetricKey)
        let newChainCode = newExtendedKey[32..<64]
        
        let divergedKey = ExtendedPrivateKey(from: seed,
                                             key: key,
                                             precedent: (key: self.data,
                                                         chainCode: newChainCode,
                                                         fingerprint: self.publicKey.hash160[0..<4]),
                                             depth: depth,
                                             index: index.number,
                                             algorithm: self.algorithm,
                                             network: self.network)
        
        return divergedKey
    }
}
