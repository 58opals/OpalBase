// Opal Base by 58 Opals

import Foundation

struct Script {
    enum Representation {
        case p2pkh              // Pay-to-Public-Key-Hash (P2PKH)
        case p2sh               // Pay-to-Script-Hash (P2SH)
        case wifCompressed      // Wallet Import Format (WIF) for compressed public keys
        case wifUncompressed    // Wallet Import Format (WIF) for uncompressed public keys
        case extendedPrivateKey // Extended private key (xprv)
        case extendedPublicKey  // Extended public key (xpub)
        
        var prefix: Data {
            switch self {
            case .p2pkh: return Data([0x00])
            case .p2sh: return Data([0x05])
            case .wifCompressed: return Data([0x80])
            case .wifUncompressed: return Data([0x80])
            case .extendedPrivateKey: return Data([0x04, 0x88, 0xAD, 0xE4])
            case .extendedPublicKey: return Data([0x04, 0x88, 0xB2, 0x1E])
            }
        }
        
        var hex: String {
            switch self {
            case .p2pkh: return "00"
            case .p2sh: return "05"
            case .wifCompressed: return "80"
            case .wifUncompressed: return "80"
            case .extendedPrivateKey: return "0488ADE4"
            case .extendedPublicKey: return "0488B21E"
            }
        }
    }
}
