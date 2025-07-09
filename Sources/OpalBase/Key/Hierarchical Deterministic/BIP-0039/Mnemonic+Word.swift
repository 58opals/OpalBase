// Mnemonic+Word.swift

import Foundation

extension Mnemonic {
    struct Word {}
}

extension Mnemonic.Word {
    static func loadWordList(language: Language = .english) throws -> [String] {
        guard let filePath = language.filePath else { throw Error.cannotLoadMnemonicWords }
        let contents = try String(contentsOfFile: filePath, encoding: .utf8)
        let words = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return words
    }
    
    static func detectLanguage(of words: [String]) throws -> Language {
        for language in Language.allCases {
            let wordList = try loadWordList(language: language)
            let wordSet = Set(wordList)
            if words.allSatisfy({ wordSet.contains($0) }) {
                return language
            }
        }
        throw Error.unknownLanguage
    }
    
    static func validateMnemonicWords(_ words: [String]) throws -> Bool {
        let language = try detectLanguage(of: words)
        let wordList = try loadWordList(language: language)
        let wordSet = Set(wordList)
        
        for word in words {
            if !wordSet.contains(word) {
                throw Error.invalidMnemonicWord(word)
            }
        }
        
        let bitString = try words.map { word -> String in
            guard let index = wordList.firstIndex(of: word) else { throw Error.invalidMnemonicWord(word) }
            return String(index, radix: 2).padLeft(to: 11)
        }.joined()
        
        let checksumLength = bitString.count / 33
        let entropyBits = bitString.prefix(bitString.count - checksumLength)
        let checksumBits = bitString.suffix(checksumLength)
        
        let entropyData = String(entropyBits).convertBitToData()
        let calculatedChecksum = SHA256.hash(entropyData).convertToBitString().prefix(checksumLength)
        
        if checksumBits != calculatedChecksum {
            throw Error.invalidChecksum
        }
        
        return true
    }
}
