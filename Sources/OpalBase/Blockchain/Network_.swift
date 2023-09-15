// Opal Base by 58 Opals

import Foundation

protocol Network {
    var name: String { get }
    var scheme: String { get }
    var network: BitcoinCash.Network { get }
    var magic: UInt32 { get }
    var port: UInt32 { get }
    var dnsSeeds: [String] { get }
    var genesisBlockHash: Data { get }
}
