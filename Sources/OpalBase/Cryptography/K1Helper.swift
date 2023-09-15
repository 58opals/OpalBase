// Opal Base by 58 Opals

import Foundation
import K1

struct K1Helper {
    func generatePublicKey(from basicPrivateKey: BasicPrivateKey) -> BasicPublicKey {
        switch basicPrivateKey.algorithm {
        case .ecdsa:
            let privateKey = try! K1.ECDSA.PrivateKey(rawRepresentation: basicPrivateKey.data)
            let publicKey = try! K1.ECDSA.PublicKey(rawRepresentation: privateKey.publicKey.rawRepresentation)
            
            let uncompressed = Data([UInt8(0x04)]) + (publicKey.rawRepresentation)
            let hash160 = Cryptography.hash160.hash(data: publicKey.compressedRepresentation)
            
            return BasicPublicKey(algorithm: basicPrivateKey.algorithm,
                                  network: basicPrivateKey.network,
                                  uncompressed: uncompressed,
                                  compressed: publicKey.compressedRepresentation,
                                  der: publicKey.derRepresentation,
                                  pem: publicKey.pemRepresentation,
                                  x963: publicKey.derRepresentation,
                                  hash160: hash160)
        case .schnorr:
            let privateKey = try! K1.Schnorr.PrivateKey(rawRepresentation: basicPrivateKey.data)
            let publicKey = try! K1.Schnorr.PublicKey(rawRepresentation: privateKey.publicKey.rawRepresentation)
            
            let uncompressed = Data([UInt8(0x04)]) + (publicKey.rawRepresentation)
            let hash160 = Cryptography.hash160.hash(data: publicKey.compressedRepresentation)
            
            return BasicPublicKey(algorithm: basicPrivateKey.algorithm,
                                  network: basicPrivateKey.network,
                                  uncompressed: uncompressed,
                                  compressed: publicKey.compressedRepresentation,
                                  der: publicKey.derRepresentation,
                                  pem: publicKey.pemRepresentation,
                                  x963: publicKey.derRepresentation,
                                  hash160: hash160)
        }
    }
    
    func generatePublicKey(from extendedPrivateKey: ExtendedPrivateKey) -> ExtendedPublicKey {
        let basicPrivateKey = extendedPrivateKey.basicPrivateKey
        
        switch extendedPrivateKey.algorithm {
        case .ecdsa:
            let privateKey = try! K1.ECDSA.PrivateKey(rawRepresentation: basicPrivateKey.data)
            let publicKey = try! K1.ECDSA.PublicKey(rawRepresentation: privateKey.publicKey.rawRepresentation)
            
            let uncompressed = Data([UInt8(0x04)]) + (publicKey.rawRepresentation)
            let hash160 = Cryptography.hash160.hash(data: publicKey.compressedRepresentation)
            
            let basicPublicKey = BasicPublicKey(algorithm: basicPrivateKey.algorithm,
                                                network: basicPrivateKey.network,
                                                uncompressed: uncompressed,
                                                compressed: publicKey.compressedRepresentation,
                                                der: publicKey.derRepresentation,
                                                pem: publicKey.pemRepresentation,
                                                x963: publicKey.derRepresentation,
                                                hash160: hash160)
            
            return ExtendedPublicKey(from: basicPublicKey,
                                     precedentFingerprint: extendedPrivateKey.precedent.fingerprint,
                                     chainCode: extendedPrivateKey.chainCode,
                                     depth: extendedPrivateKey.depth)
        case .schnorr:
            let privateKey = try! K1.Schnorr.PrivateKey(rawRepresentation: basicPrivateKey.data)
            let publicKey = try! K1.Schnorr.PublicKey(rawRepresentation: privateKey.publicKey.rawRepresentation)
            
            let uncompressed = Data([UInt8(0x04)]) + (publicKey.rawRepresentation)
            let hash160 = Cryptography.hash160.hash(data: publicKey.compressedRepresentation)
            
            let basicPublicKey = BasicPublicKey(algorithm: basicPrivateKey.algorithm,
                                                network: basicPrivateKey.network,
                                                uncompressed: uncompressed,
                                                compressed: publicKey.compressedRepresentation,
                                                der: publicKey.derRepresentation,
                                                pem: publicKey.pemRepresentation,
                                                x963: publicKey.derRepresentation,
                                                hash160: hash160)
            return ExtendedPublicKey(from: basicPublicKey,
                                     precedentFingerprint: extendedPrivateKey.precedent.fingerprint,
                                     chainCode: extendedPrivateKey.chainCode,
                                     depth: extendedPrivateKey.depth)
        }
    }
    
    func sign(message: Data, doubleHash: Bool = true, from privateKey: BasicPrivateKey) -> Data {
        let hashedMessage = switch doubleHash {
        case true: Cryptography.sha256.doubleHash(data: message)
        case false: Cryptography.sha256.hash(data: message)
        }
        
        let signature = try! K1.ECDSA.PrivateKey(rawRepresentation: privateKey.data).signature(for: hashedMessage).rawRepresentation
        return signature
    }
    
    func validate(signature: Data, for message: Data, from basicPublicKey: BasicPublicKey) -> Bool {
        let publicKey = try! K1.ECDSA.PublicKey(compressedRepresentation: basicPublicKey.compressed)
        let validation = publicKey.isValidSignature(try! .init(rawRepresentation: signature), hashed: message)

        return validation
    }
}
