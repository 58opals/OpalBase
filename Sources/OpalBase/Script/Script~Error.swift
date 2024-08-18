import Foundation

extension Script {
    public enum Error: Swift.Error {
        case cannotDecodeScript
        
        case invalidP2PKScript
        case invalidP2PKHScript
        case invalidP2SHScript
        case invalidP2MSScript
    }
}

