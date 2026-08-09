// OpalBase+Network+Environment~Mosaic.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Network.Environment {
    func supportsMosaicProfile(_ profile: OpalFusion.Mosaic.Profile) -> Bool {
        switch (self, profile) {
        case (.chipnet, .opalV0), (.mainnet, .opalMainnetAlpha):
            true
        default:
            false
        }
    }

    var mosaicGenesisHash: [UInt8] {
        let hexadecimalString = switch self {
        case .mainnet:
            "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        case .testnet:
            "000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943"
        case .chipnet:
            "000000001dd410c49a788668ce26751718cc797474d3152a5fc073dd44fd9f7b"
        }
        guard let hash = try? Data(hexadecimalString: hexadecimalString) else {
            preconditionFailure("Invalid repository-owned network genesis hash.")
        }
        return [UInt8](hash)
    }
}
#endif
