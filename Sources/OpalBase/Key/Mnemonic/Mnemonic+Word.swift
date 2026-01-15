// Mnemonic+Word.swift

import Foundation

extension Mnemonic {
    enum Word {}
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
        
        let entropyData = String(entropyBits).convertBitsToData()
        let calculatedChecksum = SHA256.hash(entropyData).convertToBitString().prefix(checksumLength)
        
        if checksumBits != calculatedChecksum {
            throw Error.invalidChecksum
        }
        
        return true
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
