// Mnemonic+WordList.swift

import Foundation

extension Mnemonic {
    public struct WordList: Sendable {
        public let language: Mnemonic.Word.Language
        public let words: [String]
        public let wordSet: Set<String>
        public let indexByWord: [String: Int]
        
        public init(language: Mnemonic.Word.Language) throws {
            let words = try Mnemonic.Word.loadWordList(language: language)
            self.language = language
            self.words = words
            self.wordSet = Set(words)
            self.indexByWord = Dictionary(
                uniqueKeysWithValues: words.enumerated().map { ($0.element, $0.offset) }
            )
        }
    }
}
