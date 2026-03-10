// OpalBase+Storage+StoredMnemonic.swift

import Foundation

extension _OpalBase.Storage {
    public struct StoredMnemonic: Sendable {
        public let words: [String]
        public let passphrase: String
        
        public init(words: [String], passphrase: String) {
            self.words = words
            self.passphrase = passphrase
        }
    }
}

extension _OpalBase.Storage.StoredMnemonic {
    struct Payload: Codable {
        public let words: [String]
        public let passphrase: String
    }
}
