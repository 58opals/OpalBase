import Foundation

extension Mnemonic {
    enum Error: Swift.Error {
        case entropyGenerationFailed
        case invalidMnemonicWords
        case cannotLoadMnemonicWords
        case cannotConvertStringToData
    }
}
