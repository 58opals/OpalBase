import Foundation
import BigInt
import secp256k1

struct ECDSA {
    static let numberOfPointsOnTheCurveWeCanHit = BigUInt("115792089237316195423570985008687907852837564279074904382605163141518161494337")
}

extension ECDSA {
    static func getPublicKey(from privateKey: Data) throws -> secp256k1.Signing.PublicKey {
        let secp256k1PrivateKey = try secp256k1.Signing.PrivateKey(dataRepresentation: privateKey)
        return secp256k1PrivateKey.publicKey
    }
}

extension ECDSA {
    enum SignatureFormat {
        case ecdsa(ECDSA)
        case schnorr
        
        enum ECDSA {
            case raw
            case compact
            case der
        }
    }
}

extension ECDSA {
    static func sign(message: Data, with privateKey: Data, in format: SignatureFormat) throws -> Data {
        switch format {
        case .ecdsa(let ecdsa):
            let ecdsaPrivateKey = try secp256k1.Signing.PrivateKey(dataRepresentation: privateKey)
            switch ecdsa {
            case .raw:
                let signature = try ecdsaPrivateKey.signature(for: message)
                return signature.dataRepresentation
            case .compact:
                let signature = try ecdsaPrivateKey.signature(for: message)
                return try signature.compactRepresentation
            case .der:
                let signature = try ecdsaPrivateKey.signature(for: message)
                return try signature.derRepresentation
            }
            
        case .schnorr:
            let schnorrPrivateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey)
            let schnorrSignature = try schnorrPrivateKey.signature(for: message)
            return schnorrSignature.dataRepresentation
        }
    }
}

extension ECDSA {
    static func verify(signature: Data, message: Data, publicKey: PublicKey, format: SignatureFormat) throws -> Bool {
        let compressedPublicKey = publicKey.compressedData
        guard compressedPublicKey.count == 33 else { throw Error.invalidCompressedPublicKeyLength }
        let prefix = compressedPublicKey[0]
        guard prefix == 0x02 || prefix == 0x03 else { throw Error.invalidCompressedPublicKeyPrefix }
        
        switch format {
        case .ecdsa(let ecdsa):
            let ecdsaPublicKey = try secp256k1.Signing.PublicKey(dataRepresentation: compressedPublicKey, format: .compressed)
            switch ecdsa {
            case .raw:
                let ecdsaSignature = try secp256k1.Signing.ECDSASignature(dataRepresentation: signature)
                return ecdsaPublicKey.isValidSignature(ecdsaSignature, for: message)
            case .compact:
                let ecdsaSignature = try secp256k1.Signing.ECDSASignature(compactRepresentation: signature)
                return ecdsaPublicKey.isValidSignature(ecdsaSignature, for: message)
            case .der:
                let ecdsaSignature = try secp256k1.Signing.ECDSASignature(derRepresentation: signature)
                return ecdsaPublicKey.isValidSignature(ecdsaSignature, for: message)
            }
        case .schnorr:
            let xCoordinate = compressedPublicKey[1..<33]
            let schnorrPublicKey = secp256k1.Schnorr.XonlyKey(dataRepresentation: xCoordinate)
            let schnorrSignature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: signature)
            return schnorrPublicKey.isValidSignature(schnorrSignature, for: message)
        }
    }
}
