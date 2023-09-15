// Opal Base by 58 Opals

import Foundation

import Foundation

struct Mnemonic {
    let words: [String]
    
    init(from words: [String]) {
        switch words.count {
        case 12, 24:
            self.words = words
        default: fatalError()
        }
    }
    
    init(highSecurity: Bool = true, language: BIP0039.Language = .english) {
        let entropy = Data.generateSecuredRandomBytes(count: highSecurity ? 32 : 16)
        let length = (entropy.count * 8) / 32
        let sha256 = Cryptography.sha256.hash(data: entropy)
        let checksumBits = Data(sha256).bits.prefix(length)
        let checksum = Array(checksumBits)
        let bits = entropy.bits + checksum
        
        var words: [String] = .init()

        for round in 0..<(bits.count/11) {
            let index = round*11
            let wordBits = bits[index..<(index+11)]
            
            var wordIndex: UInt16 = 0
            let reversedArray = Array(wordBits.reversed())

            for index in 0..<reversedArray.count {
                let digit = UInt16(1) << index
                let digitNumber = UInt16(reversedArray[index].rawValue) * digit
                wordIndex += digitNumber
            }
            
            words.append(BIP0039(language: language).words[Int(wordIndex)])
        }
        
        self.words = words
    }
}

extension Mnemonic {
    private func createSeed(with passPhrase: String = "") -> Data {
        guard let password = words.joined(separator: " ").decomposedStringWithCompatibilityMapping.data(using: .utf8) else { fatalError() }
        guard let salt = ("mnemonic" + passPhrase).decomposedStringWithCompatibilityMapping.data(using: .utf8) else { fatalError() }
        
        let seed: Data = .init(Cryptography.pbkdf2.getPBKDF2(password: .init(password),
                                                             salt: .init(salt)))
        print(seed.hexadecimal)
        return seed
    }
    
    func createRootPrivateKey(with passPhrase: String = "",
                              key: Data = "Bitcoin seed".data(using: .ascii)!,
                              algorithm: Cryptography.Algorithm) -> ExtendedPrivateKey {
        return .init(from: createSeed(with: passPhrase),
                     key: key,
                     algorithm: algorithm)
    }
}

extension Mnemonic: CustomStringConvertible {
    var description: String {
        words.joined(separator: " ")
    }
}
