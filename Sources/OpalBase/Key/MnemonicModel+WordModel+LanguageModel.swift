// MnemonicModel+WordModel+LanguageModel.swift

import Foundation

extension MnemonicModel.WordModel {
    public enum LanguageModel: Sendable, CaseIterable {
        case english
        case korean
        
        var filePath: String? {
            switch self {
            case .english:
                return Bundle.module.path(forResource: "English", ofType: "txt")
            case .korean:
                return Bundle.module.path(forResource: "Korean", ofType: "txt")
            }
        }
    }
}
