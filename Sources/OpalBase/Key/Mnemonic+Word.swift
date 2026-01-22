// Mnemonic+Word.swift

import Foundation

extension Mnemonic {
    public enum Word {}
}

extension Mnemonic.Word {
    static func loadWordList(language: Language = .english) throws -> [String] {
        guard let filePath = language.filePath else { throw Error.cannotLoadMnemonicWords }
        let contents = try String(contentsOfFile: filePath, encoding: .utf8)
        let words = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return words
    }
    
    static func detectLanguage(of words: [String]) throws -> Mnemonic.WordList {
        let wordLists = try loadWordLists()
        return try detectLanguage(of: words, wordLists: wordLists)
    }
    
    static func detectLanguage(
        of words: [String],
        wordLists: [Language: Mnemonic.WordList]
    ) throws -> Mnemonic.WordList {
        for language in Language.allCases {
            guard let wordList = wordLists[language] else { continue }
            if words.allSatisfy({ wordList.wordSet.contains($0) }) {
                return wordList
            }
        }
        throw Error.unknownLanguage
    }
    
    static func validateMnemonicWords(_ words: [String]) throws -> Bool {
        let wordList = try detectLanguage(of: words)
        return try validateMnemonicWords(words, wordList: wordList)
    }
    
    static func validateMnemonicWords(_ words: [String], wordList: Mnemonic.WordList) throws -> Bool {
        let wordToIndex = wordList.indexByWord
        
        var bitString = String()
        bitString.reserveCapacity(words.count * 11)
        
        for word in words {
            guard let index = wordToIndex[word] else { throw Error.invalidMnemonicWord(word) }
            bitString.append(contentsOf: String(index, radix: 2).padLeft(to: 11))
        }
        
        let checksumLength = bitString.count / 33
        let entropyBits = bitString.prefix(bitString.count - checksumLength)
        let checksumBits = bitString.suffix(checksumLength)
        
        let entropyData = String(entropyBits).convertBitsToData()
        let calculatedChecksum = SHA256.hash(entropyData).convertToBitString().prefix(checksumLength)
        
        if checksumBits != calculatedChecksum {
            throw Error.invalidChecksum
        }
        
        return true
    }
    
    static func validateMnemonicWords(
        _ words: [String],
        wordLists: [Language: Mnemonic.WordList]
    ) throws -> Bool {
        let wordList = try detectLanguage(of: words, wordLists: wordLists)
        return try validateMnemonicWords(words, wordList: wordList)
    }
}

extension Mnemonic.Word {
    enum Error: Swift.Error {
        case cannotLoadMnemonicWords
        case invalidMnemonicWord(String)
        case invalidChecksum
        case unknownLanguage
    }
}

private extension Mnemonic.Word {
    static func loadWordLists() throws -> [Language: Mnemonic.WordList] {
        var wordListsByLanguage: [Language: Mnemonic.WordList] = .init()
        for language in Language.allCases {
            wordListsByLanguage[language] = try Mnemonic.WordList(language: language)
        }
        return wordListsByLanguage
    }
    
    static func makeBitValues(from index: Int, bitCount: Int) -> [UInt8] {
        var values: [UInt8] = .init(repeating: 0, count: bitCount)
        for position in 0..<bitCount {
            let shift = bitCount - position - 1
            let bitValue = (index >> shift) & 1
            values[position] = UInt8(bitValue)
        }
        return values
    }
    
    static func makeData(from bitValues: [UInt8]) throws -> Data {
        guard bitValues.count % 8 == 0 else { throw Error.invalidChecksum }
        var bytes: [UInt8] = .init()
        bytes.reserveCapacity(bitValues.count / 8)
        
        for offset in stride(from: 0, to: bitValues.count, by: 8) {
            let endOffset = offset + 8
            var value: UInt8 = 0
            for bit in bitValues[offset..<endOffset] {
                value = (value << 1) | bit
            }
            bytes.append(value)
        }
        return Data(bytes)
    }
}
