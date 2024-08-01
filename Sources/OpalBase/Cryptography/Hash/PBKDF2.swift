import Foundation
import CryptoSwift

struct PBKDF2 {
    static func hash(password: String, salt: String, iterations: Int = 2048, keyLength: Int = 64) throws -> Data {
        let password: Array<UInt8> = Data(password.utf8).bytes
        let salt: Array<UInt8> = Data(salt.utf8).bytes
        let pbkdf2 = try PKCS5.PBKDF2(password: password, salt: salt, iterations: iterations, keyLength: keyLength, variant: .sha2(.sha512)).calculate()
        
        return Data(pbkdf2)
    }
}
