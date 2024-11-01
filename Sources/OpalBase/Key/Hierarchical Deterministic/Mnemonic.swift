import Foundation

public struct Mnemonic {
    public let words: [String]
    public let seed: Data
    
    public init(length: Length = .long) throws {
        let entropy = try Mnemonic.generateEntropy(numberOfBits: length.numberOfBits)
        let mnemonicWords = try Mnemonic.generateMnemonicWords(from: entropy)
        let seed = try Mnemonic.generateSeed(from: mnemonicWords)
        
        self.words = mnemonicWords
        self.seed = seed
    }
    
    public init(words: [String]) throws {
        guard try Word.validateMnemonicWords(words) else { throw Error.invalidMnemonicWords }
        
        self.words = words
        self.seed = try Mnemonic.generateSeed(from: words)
    }
    
    static func generateEntropy(numberOfBits: Int) throws -> Data {
        guard numberOfBits % 32 == 0, numberOfBits >= 128, numberOfBits <= 256 else { throw Error.entropyGenerationFailed }
        
        var randomBytes = [UInt8](repeating: 0, count: numberOfBits / 8)
        let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard result == errSecSuccess else { throw Error.entropyGenerationFailed }
        
        return Data(randomBytes)
    }
    
    static func generateMnemonicWords(from entropy: Data) throws -> [String] {
        let sha256 = SHA256.hash(entropy)
        let checksumLength = (entropy.count * 8) / 32
        let checksumBits = sha256.prefix(1).convertToBitString().prefix(checksumLength)
        let entropyWithChecksumBits = entropy.convertToBitString() + checksumBits
        let entropyBits = entropyWithChecksumBits
        
        let wordList = try Word.loadWordList()
        
        var mnemonicWords = [String]()
        for bitIndex in stride(from: 0, to: entropyBits.count, by: 11) {
            let startIndex = entropyBits.index(entropyBits.startIndex, offsetBy: bitIndex)
            let endIndex = entropyBits.index(startIndex, offsetBy: 11, limitedBy: entropyBits.endIndex) ?? entropyBits.endIndex
            let bitRange = entropyBits[startIndex..<endIndex]
            let index = Int(bitRange, radix: 2)!
            mnemonicWords.append(wordList[index])
        }
        
        return mnemonicWords
    }
    
    static func generateSeed(from mnemonicWords: [String], passphrase: String = "") throws -> Data {
        let words = mnemonicWords.joined(separator: " ")
        
        let password = Data(words.utf8).bytes
        let salt = Data(("mnemonic" + passphrase).utf8).bytes
        let iterations = 2048
        let keyLength = 64
        
        return try PBKDF2(password: password, saltBytes: salt, iterationCount: iterations, derivedKeyLength: keyLength).deriveKey()
    }
}

extension Mnemonic: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.words)
        hasher.combine(self.seed)
    }
}
