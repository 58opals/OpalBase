// OpalBase+Mnemonic+WordListModel.swift

import Foundation

extension _OpalBase.Mnemonic {
    public struct WordListModel: Sendable {
        public let language: OpalBase.Mnemonic.WordModel.LanguageModel
        public let words: [String]
        public let wordSet: Set<String>
        public let indexByWord: [String: Int]
        
        public init(language: OpalBase.Mnemonic.WordModel.LanguageModel) throws {
            let words = try OpalBase.Mnemonic.WordModel.loadWordList(language: language)
            self.language = language
            self.words = words
            self.wordSet = Set(words)
            self.indexByWord = Dictionary(
                uniqueKeysWithValues: words.enumerated().map { ($0.element, $0.offset) }
            )
        }
    }
}
