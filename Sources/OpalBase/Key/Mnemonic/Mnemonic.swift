// Mnemonic.swift

import Foundation

public struct Mnemonic {
    public let words: [String]
    public let seed: Data
    public let passphrase: String
    
    public init(length: Length = .long, passphrase: String = "") throws {
        let entropy = try Mnemonic.generateEntropy(numberOfBits: length.numberOfBits)
        let mnemonicWords = try Mnemonic.generateMnemonicWords(from: entropy)
        let seed = try Mnemonic.generateSeed(from: mnemonicWords, passphrase: passphrase)
        
        self.words = mnemonicWords
        self.seed = seed
        self.passphrase = passphrase
    }
    
    public init(words: [String], passphrase: String = "") throws {
        guard try Word.validateMnemonicWords(words) else { throw Error.invalidMnemonicWords }
        
        self.words = words
        self.seed = try Mnemonic.generateSeed(from: words, passphrase: passphrase)
        self.passphrase = passphrase
    }
    
    static func generateEntropy(numberOfBits: Int) throws -> Data {
        guard numberOfBits % 32 == 0, numberOfBits >= 128, numberOfBits <= 256 else { throw Error.entropyGenerationFailed }
        
        let byteCount = numberOfBits / 8
        let randomBytes: [UInt8]
        do {
            randomBytes = try SecureRandom.makeBytes(count: byteCount)
        } catch {
            throw Error.entropyGenerationFailed
        }
        
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
        let mnemonicSentence = mnemonicWords.joined(separator: " ")
        let normalizedMnemonic = mnemonicSentence.decomposedStringWithCompatibilityMapping
        let normalizedPassphrase = passphrase.decomposedStringWithCompatibilityMapping
        
        let password = Array(normalizedMnemonic.utf8)
        let saltString = "mnemonic" + normalizedPassphrase
        let salt = Array(saltString.utf8)
        let iterations = 2048
        let keyLength = 64
        
        return try PBKDF2(password: password, saltBytes: salt, iterationCount: iterations, derivedKeyLength: keyLength).deriveKey()
    }
}

extension Mnemonic: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.words)
        hasher.combine(self.seed)
        hasher.combine(self.passphrase)
    }
}

extension Mnemonic: Sendable {}

extension Mnemonic {
    enum Error: Swift.Error {
        case entropyGenerationFailed
        case invalidMnemonicWords
        case cannotLoadMnemonicWords
        case cannotConvertStringToData
    }
}
