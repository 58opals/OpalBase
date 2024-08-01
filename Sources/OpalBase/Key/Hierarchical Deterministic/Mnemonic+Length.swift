import Foundation

extension Mnemonic {
    enum Length {
        case short
        case long
        
        var numberOfBits: Int {
            switch self {
            case .short: return 128
            case .long: return 256
            }
        }
    }
}
