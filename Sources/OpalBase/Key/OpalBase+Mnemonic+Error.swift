// OpalBase+Mnemonic+Error.swift

import Foundation

extension _OpalBase.Mnemonic {
    enum Error: Swift.Error {
        case entropyGenerationFailed
        case invalidMnemonicWords
        case cannotLoadMnemonicWords
        case cannotConvertStringToData
    }
}
