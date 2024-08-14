import Foundation

struct PublicKey {
    let compressedData: Data
    
    init(privateKey: PrivateKey) throws {
        self.compressedData = try ECDSA.getPublicKey(from: privateKey.rawData).dataRepresentation
    }
    
    init(compressedData: Data) throws {
        guard compressedData.count == 33 else { throw Error.invalidLength }
        self.compressedData = compressedData
    }
}

extension PublicKey {
    private var hash: Data {
        let sha256 = SHA256.hash(compressedData)
        let ripemd160 = RIPEMD160.hash(sha256)
        let hash = ripemd160
        return hash
    }
    
    struct Hash {
        let data: Data
        
        init(_ data: Data) {
            self.data = data
        }
        
        init(publicKey: PublicKey) {
            self.data = publicKey.hash
        }
    }
}
