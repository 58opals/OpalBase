// OpalBase+Script+Error.swift

import Foundation

extension _OpalBase.Script {
    enum Error: Swift.Error, Equatable {
        case cannotDecodeScript
        
        case invalidP2PKScript
        case invalidP2PKHScript
        case invalidP2SHScript
        case invalidP2MSScript
    }
}
