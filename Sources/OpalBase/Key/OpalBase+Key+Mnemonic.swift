// OpalBase+Key+Mnemonic.swift

import Foundation
import OpalCrypto

extension _OpalBase.Key {
    public struct Mnemonic: Sendable, Equatable {
        public enum Length: Int, CaseIterable, Sendable {
            case words12 = 12
            case words15 = 15
            case words18 = 18
            case words21 = 21
            case words24 = 24
        }

        public struct Word: Sendable, Hashable, LosslessStringConvertible {
            public enum Language: String, CaseIterable, Sendable {
                case english
                case korean
            }

            public let text: String

            public init(_ description: String) {
                self.text = OpalCrypto.Key.Mnemonic.Word(description).description
            }

            public var description: String {
                text
            }
        }

        public struct WordList: Sendable, Equatable {
            public let language: Word.Language
            public let words: [Word]

            private let indexLookup: [String: Int]

            public var count: Int {
                words.count
            }

            public subscript(index: Int) -> Word {
                words[index]
            }

            public static func load(_ language: Word.Language) throws -> WordList {
                do {
                    let wordList = try OpalCrypto.Key.Mnemonic.WordList.load(language.opalCryptoLanguage)
                    return WordList(
                        language: language,
                        words: wordList.words.map(Word.init(_:))
                    )
                } catch {
                    throw Mnemonic.mapError(error)
                }
            }

            public func contains(_ word: Word) -> Bool {
                indexLookup[word.text] != nil
            }

            public func index(of word: Word) -> Int? {
                indexLookup[word.text]
            }

            init(language: Word.Language, words: [Word]) {
                self.language = language
                self.words = words
                self.indexLookup = Dictionary(
                    uniqueKeysWithValues: words.enumerated().map { ($1.text, $0) }
                )
            }
        }

        public enum Error: Swift.Error, Equatable {
            case invalidWordCount(actual: Int)
            case invalidEntropyLength(actual: Int)
            case invalidWord(String)
            case invalidChecksum
            case ambiguousLanguage
            case randomGenerationFailed(status: Int32)
            case wordListResourceMissing(language: Word.Language)
            case invalidWordList(language: Word.Language, actualCount: Int)
        }

        public let words: [Word]
        public let length: Length
        public let language: Word.Language

        public var phrase: String {
            words.map(\.text).joined(separator: " ")
        }

        public init(phrase: String, language: Word.Language? = nil) throws {
            do {
                self.init(try OpalCrypto.Key.Mnemonic(
                    phrase: phrase,
                    language: language?.opalCryptoLanguage
                ))
            } catch {
                throw Self.mapError(error)
            }
        }

        public init(words: [Word], language: Word.Language? = nil) throws {
            do {
                self.init(try OpalCrypto.Key.Mnemonic(
                    words: words.map(\.opalCryptoWord),
                    language: language?.opalCryptoLanguage
                ))
            } catch {
                throw Self.mapError(error)
            }
        }

        public static func generate(length: Length, language: Word.Language) throws -> Mnemonic {
            do {
                return try Mnemonic(
                    OpalCrypto.Key.Mnemonic.generate(
                        length: length.opalCryptoLength,
                        language: language.opalCryptoLanguage
                    )
                )
            } catch {
                throw mapError(error)
            }
        }

        public func deriveSeed(passphrase: String = "") throws -> Data {
            do {
                return try makeOpalCryptoMnemonic().deriveSeed(passphrase: passphrase)
            } catch {
                throw Self.mapError(error)
            }
        }

        init(_ mnemonic: OpalCrypto.Key.Mnemonic) {
            self.words = mnemonic.words.map(Word.init(_:))
            self.length = .init(mnemonic.length)
            self.language = .init(mnemonic.language)
        }

        func makeOpalCryptoMnemonic() throws -> OpalCrypto.Key.Mnemonic {
            try OpalCrypto.Key.Mnemonic(
                words: words.map(\.opalCryptoWord),
                language: language.opalCryptoLanguage
            )
        }

        static func mapError(_ error: Swift.Error) -> Error {
            guard let mnemonicError = error as? OpalCrypto.Key.Mnemonic.Error else {
                return .invalidChecksum
            }

            switch mnemonicError {
            case .invalidWordCount(let actual):
                return .invalidWordCount(actual: actual)
            case .invalidEntropyLength(let actual):
                return .invalidEntropyLength(actual: actual)
            case .invalidWord(let word):
                return .invalidWord(word)
            case .invalidChecksum:
                return .invalidChecksum
            case .ambiguousLanguage:
                return .ambiguousLanguage
            case .randomGenerationFailed(let status):
                return .randomGenerationFailed(status: status)
            case .wordListResourceMissing(let language):
                return .wordListResourceMissing(language: .init(language))
            case .invalidWordList(let language, let actualCount):
                return .invalidWordList(language: .init(language), actualCount: actualCount)
            }
        }
    }
}

private extension _OpalBase.Key.Mnemonic.Length {
    init(_ length: OpalCrypto.Key.Mnemonic.Length) {
        switch length {
        case .words12:
            self = .words12
        case .words15:
            self = .words15
        case .words18:
            self = .words18
        case .words21:
            self = .words21
        case .words24:
            self = .words24
        }
    }

    var opalCryptoLength: OpalCrypto.Key.Mnemonic.Length {
        switch self {
        case .words12:
            return .words12
        case .words15:
            return .words15
        case .words18:
            return .words18
        case .words21:
            return .words21
        case .words24:
            return .words24
        }
    }
}

private extension _OpalBase.Key.Mnemonic.Word.Language {
    init(_ language: OpalCrypto.Key.Mnemonic.Word.Language) {
        switch language {
        case .english:
            self = .english
        case .korean:
            self = .korean
        }
    }

    var opalCryptoLanguage: OpalCrypto.Key.Mnemonic.Word.Language {
        switch self {
        case .english:
            return .english
        case .korean:
            return .korean
        }
    }
}

private extension _OpalBase.Key.Mnemonic.Word {
    init(_ word: OpalCrypto.Key.Mnemonic.Word) {
        self.init(word.description)
    }

    var opalCryptoWord: OpalCrypto.Key.Mnemonic.Word {
        .init(text)
    }
}
