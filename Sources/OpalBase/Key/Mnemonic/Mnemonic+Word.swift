// Mnemonic+Word.swift

import Foundation

extension Mnemonic {
    enum Word {}
}

extension Mnemonic.Word {
    private static let wordListCache = WordListCache()
    
    static func loadWordList(language: Language = .english) throws -> [String] {
        try wordListCache.loadWordList(for: language) {
            guard let filePath = language.filePath else { throw Error.cannotLoadMnemonicWords }
            let contents = try String(contentsOfFile: filePath, encoding: .utf8)
            let words = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return words
        }
    }
    
    static func detectLanguage(of words: [String]) throws -> Language {
        for language in Language.allCases {
            let wordSet = try wordListCache.loadWordSet(for: language) {
                try loadWordList(language: language)
            }
            if words.allSatisfy({ wordSet.contains($0) }) {
                return language
            }
        }
        throw Error.unknownLanguage
    }
    
    static func validateMnemonicWords(_ words: [String]) throws -> Bool {
        let language = try detectLanguage(of: words)
        let wordList = try loadWordList(language: language)
        let wordSet = try wordListCache.loadWordSet(for: language) {
            wordList
        }
        
        for word in words {
            if !wordSet.contains(word) {
                throw Error.invalidMnemonicWord(word)
            }
        }
        
        var bitValues: [UInt8] = .init()
        bitValues.reserveCapacity(words.count * 11)
        
        for word in words {
            guard let index = wordList.firstIndex(of: word) else { throw Error.invalidMnemonicWord(word) }
            bitValues.append(contentsOf: makeBitValues(from: index, bitCount: 11))
        }
        
        let checksumLength = bitValues.count / 33
        let entropyBitCount = bitValues.count - checksumLength
        let entropyBits = Array(bitValues.prefix(entropyBitCount))
        let checksumBits = Array(bitValues.suffix(checksumLength))
        guard entropyBitCount % 8 == 0 else { throw Error.invalidChecksum }
        
        let entropyData = try makeData(from: entropyBits)
        let calculatedChecksum = Mnemonic.makeBitValues(from: SHA256.hash(entropyData), limit: checksumLength)
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

private final class WordListCache {
    private var wordLists: [Mnemonic.Language: [String]] = .init()
    private var wordSets: [Mnemonic.Language: Set<String>] = .init()
    private let lock = NSLock()
    
    func loadWordList(for language: Mnemonic.Language,
                      loader: () throws -> [String]) rethrows -> [String] {
        lock.lock()
        if let wordList = wordLists[language] {
            lock.unlock()
            return wordList
        }
        lock.unlock()
        
        let wordList = try loader()
        let wordSet = Set(wordList)
        
        lock.lock()
        wordLists[language] = wordList
        wordSets[language] = wordSet
        lock.unlock()
        return wordList
    }
    
    func loadWordSet(for language: Mnemonic.Language,
                     loader: () throws -> [String]) rethrows -> Set<String> {
        lock.lock()
        if let wordSet = wordSets[language] {
            lock.unlock()
            return wordSet
        }
        lock.unlock()
        
        let wordList = try loader()
        let wordSet = Set(wordList)
        
        lock.lock()
        wordLists[language] = wordList
        wordSets[language] = wordSet
        lock.unlock()
        return wordSet
    }
}
