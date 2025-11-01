// Storage+Mnemonic.swift

import Foundation

extension Storage {
    public struct Mnemonic: Sendable {
        var words: [String]
        var passphrase: String
    }
}
