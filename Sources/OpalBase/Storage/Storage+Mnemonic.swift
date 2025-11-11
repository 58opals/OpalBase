// Storage+Mnemonic.swift

import Foundation

extension Storage {
    public struct Mnemonic: Sendable {
        public let words: [String]
        public let passphrase: String
        
        public init(words: [String], passphrase: String) {
            self.words = words
            self.passphrase = passphrase
        }
    }
}

extension Storage.Mnemonic {
    struct Payload: Codable {
        public let words: [String]
        public let passphrase: String
    }
}
