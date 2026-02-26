// MnemonicModel+WordListModel.swift

import Foundation

extension MnemonicModel {
    public struct WordListModel: Sendable {
        public let language: MnemonicModel.WordModel.LanguageModel
        public let words: [String]
        public let wordSet: Set<String>
        public let indexByWord: [String: Int]
        
        public init(language: MnemonicModel.WordModel.LanguageModel) throws {
            let words = try MnemonicModel.WordModel.loadWordList(language: language)
            self.language = language
            self.words = words
            self.wordSet = Set(words)
            self.indexByWord = Dictionary(
                uniqueKeysWithValues: words.enumerated().map { ($0.element, $0.offset) }
            )
        }
    }
}
