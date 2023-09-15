// Opal Base by 58 Opals

import Foundation

public struct Blockchain {
    let blocks: [Block]
}

extension Blockchain {
    enum CoinType {
        case bitcoin, bitcoinCash
    }
}
