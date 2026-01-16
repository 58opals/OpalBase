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
    
    public init(
        words: [String],
        passphrase: String = "",
        wordList: Mnemonic.WordList
    ) throws {
        guard try Word.validateMnemonicWords(words, wordList: wordList) else { throw Error.invalidMnemonicWords }
        
        self.words = words
        self.seed = try Mnemonic.generateSeed(from: words, passphrase: passphrase)
        self.passphrase = passphrase
    }
    
    public init(
        words: [String],
        passphrase: String = "",
        wordLists: [Mnemonic.Word.Language: Mnemonic.WordList]
    ) throws {
        guard try Word.validateMnemonicWords(words, wordLists: wordLists) else { throw Error.invalidMnemonicWords }
        
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
        let checksumLength = (entropy.count * 8) / 32
        let checksumBits = Mnemonic.makeBitValues(from: SHA256.hash(entropy), limit: checksumLength)
        let entropyBits = Mnemonic.makeBitValues(from: entropy)
        let bitValues = entropyBits + checksumBits
        guard bitValues.count % 11 == 0 else { throw Error.cannotConvertStringToData }
        
        let wordList = try Word.loadWordList()
        
        var mnemonicWords: [String] = .init()
        mnemonicWords.reserveCapacity(bitValues.count / 11)
        
        for offset in stride(from: 0, to: bitValues.count, by: 11) {
            let endOffset = offset + 11
            let bitSlice = bitValues[offset..<endOffset]
            var index = 0
            for bit in bitSlice {
                index = (index << 1) | Int(bit)
            }
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
    
    static func makeBitValues(from data: Data, limit: Int? = nil) -> [UInt8] {
        let totalBitCount = data.count * 8
        let limitBitCount = limit ?? totalBitCount
        var bitValues: [UInt8] = .init()
        bitValues.reserveCapacity(limitBitCount)
        
        var remainingBits = limitBitCount
        for byte in data {
            for bitIndex in stride(from: 7, through: 0, by: -1) {
                guard remainingBits > 0 else { return bitValues }
                let bitValue = (byte >> UInt8(bitIndex)) & 1
                bitValues.append(bitValue)
                remainingBits -= 1
            }
        }
        
        return bitValues
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
