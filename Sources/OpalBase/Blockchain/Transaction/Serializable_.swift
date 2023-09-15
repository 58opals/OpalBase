// Opal Base by 58 Opals

import Foundation

protocol Serializable {
    func serialize() -> Data
}

extension Array where Element: Serializable {
    func serialize() -> Data {
        var raw: Data = .init()
        
        for element in self {
            raw += element.serialize()
        }
        
        return raw
    }
}

extension Array where Element == Transaction.Input {
    func emptyUnlockingScript() -> Data {
        var emptied: Data = .init()
            
        for element in self {
            emptied += element.emptyUnlockingScript()
        }
        
        return emptied
    }
}
