// Opal Base by 58 Opals

import Foundation

struct BitcoinCash: Network {
    public enum Network {
        case mainnet, testnet
    }
    
    let name: String = "Bitcoin Cash"
    let scheme: String = "bitcoincash"
    let network: Network
    
    let magic: UInt32 = 0xe3e1f3e8
    let port: UInt32 = 8333
    let dnsSeeds: [String] = [
        "https://seed.bchd.cash"
    ]
    let genesisBlockHash: Data = .init([0, 0, 0, 0, 0, 25, 214, 104, 156, 8, 90, 225, 101, 131, 30, 147, 79, 247, 99, 174, 70, 162, 166, 193, 114, 179, 241, 182, 10, 140, 226, 111])
}
