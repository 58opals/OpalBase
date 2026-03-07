// OpalBase.Mnemonic+WordModel+LanguageModel.swift

import Foundation

extension _OpalBase.Mnemonic.WordModel {
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
