// Opal Base by 58 Opals

import Foundation

struct ExtendedPublicKey: PublicKey, Extendable, CustomStringConvertible {
    let algorithm: Cryptography.Algorithm
    let network: BitcoinCash.Network
    
    let basicPublicKey: BasicPublicKey
    let uncompressed: Data
    let compressed: Data
    let der: Data
    let pem: String
    let x963: Data
    let hash160: Data
    
    let precedent: (key: Data?, chainCode: Data?, fingerprint: Data?)
    
    let chainCode: Data
    let depth: UInt8
    
    init(from basicPublicKey: BasicPublicKey,
         on network: BitcoinCash.Network = .mainnet,
         precedentFingerprint: Data?,
         chainCode: Data,
         depth: UInt8) {
        self.algorithm = basicPublicKey.algorithm
        self.network = network
        
        self.basicPublicKey = basicPublicKey
        self.uncompressed = basicPublicKey.uncompressed
        self.compressed = basicPublicKey.compressed
        self.der = basicPublicKey.der
        self.pem = basicPublicKey.pem
        self.x963 = basicPublicKey.x963
        self.hash160 = basicPublicKey.hash160
        
        self.precedent = (key: nil, chainCode: nil, fingerprint: precedentFingerprint)
        
        self.chainCode = chainCode
        self.depth = depth
    }
    
    func validate(signature: Data, for message: Data) -> Bool {
        let doubleHashedMessage = Cryptography.sha256.doubleHash(data: message)
        return Cryptography.k1.validate(signature: signature, for: doubleHashedMessage, from: self.basicPublicKey)
    }
    
    func diverge(to index: DerivationPath.Index, depth: UInt8) -> ExtendedPublicKey {
        fatalError()
    }
}
