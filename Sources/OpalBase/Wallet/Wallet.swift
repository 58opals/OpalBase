import Foundation

public struct Wallet {
    let rootPrivateKey: ExtendedPrivateKey
    
    init(from words: [String], algorithm: Cryptography.Algorithm = .ecdsa) {
        self.rootPrivateKey = Mnemonic(from: words).createRootPrivateKey(algorithm: algorithm)
    }
    
    init(highSecurity: Bool = true, language: BIP0039.Language = .english, algorithm: Cryptography.Algorithm = .ecdsa) {
        
        self.rootPrivateKey = Mnemonic(highSecurity: highSecurity, language: .english).createRootPrivateKey(algorithm: algorithm)
    }
}

