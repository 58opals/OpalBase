// OpalBase+Mnemonic+WordModel+Language.swift

import Foundation

extension _OpalBase.Mnemonic.WordModel {
    public enum Language: Sendable, CaseIterable {
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
