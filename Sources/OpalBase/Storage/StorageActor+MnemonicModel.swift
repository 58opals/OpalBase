// StorageActor+MnemonicModel.swift

import Foundation

extension StorageActor {
    public struct MnemonicModel: Sendable {
        public let words: [String]
        public let passphrase: String
        
        public init(words: [String], passphrase: String) {
            self.words = words
            self.passphrase = passphrase
        }
    }
}

extension StorageActor.MnemonicModel {
    struct PayloadModel: Codable {
        public let words: [String]
        public let passphrase: String
    }
}
