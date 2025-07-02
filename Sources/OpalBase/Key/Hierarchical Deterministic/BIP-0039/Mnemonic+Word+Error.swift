// Mnemonic+Word+Error.swift

import Foundation

extension Mnemonic.Word {
    enum Error: Swift.Error {
        case cannotLoadMnemonicWords
        case invalidMnemonicWord(String)
        case invalidChecksum
        case unknownLanguage
    }
}
