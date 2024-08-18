import Foundation

extension Mnemonic {
    public enum Length {
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
