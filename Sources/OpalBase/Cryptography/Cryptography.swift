// Opal Base by 58 Opals

import Foundation
import CryptoKit

struct Cryptography {
    static let k1 = K1Helper()
    static let sha256 = SHA256Helper()
    static let hash160 = HASH160Helper()
    static let pbkdf2 = PBKDF2Helper()
}

extension Cryptography {
    enum Algorithm {
        case ecdsa
        case schnorr
    }
}

extension Cryptography {
    struct SHA256Helper {
        func hash<D>(data: D) -> Data where D: DataProtocol {
            return Data(SHA256.hash(data: data))
        }
        
        func doubleHash<D>(data: D) -> Data where D: DataProtocol {
            return Data(SHA256.doubleHash(data: data))
        }
    }
    
    struct HASH160Helper {
        func hash(data: Data) -> Data {
            return HASH160.hash(data: data)
        }
    }
    
    struct PBKDF2Helper {
        typealias HMAC_KEY = SymmetricKey
        
        func getSymmetryKey(from data: Data) -> SymmetricKey { .init(data: data) }
        
        func getHMACSHA512(for data: Data,
                           sing key: SymmetricKey) -> Data { .init(HMAC<SHA512>.authenticationCode(for: data,
                                                                                                   using: key)) }
        func getPBKDF2(password: Array<UInt8>,
                       salt: Array<UInt8>,
                       iterations: Int = 2048,
                       keyLength: Int? = nil,
                       variant: CSHMAC.Variant = .sha512) -> Data { Data(try! CSPKCS5.PBKDF2(password: password,
                                                                                             salt: salt,
                                                                                             iterations: iterations,
                                                                                             keyLength: keyLength,
                                                                                             variant: variant).calculate()) }
    }
}
