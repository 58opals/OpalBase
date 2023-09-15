// Opal Base by 58 Opals

import Foundation

extension UInt32 {
    var data: Data {
        var integer = self
        return Data(bytes: &integer, count: MemoryLayout<UInt32>.size)
    }
}
