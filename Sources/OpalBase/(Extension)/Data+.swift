// Opal Base by 58 Opals

import Foundation

extension Data {
    var hexadecimal: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    func convertTo5Bit(pad: Bool) -> Data {
        var jar: Int = 0
        var bits: UInt8 = 0
        let maximumValue: Int = 0b000_11111
        var converted: [UInt8] = [UInt8]()
        for byte in self {
            jar = (jar << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                converted.append(UInt8(jar >> Int(bits) & maximumValue))
            }
        }
        
        let lastBits: UInt8 = UInt8(jar << (5 - bits) & maximumValue)
        if pad && bits > 0 {
            converted.append(lastBits)
        }
        return Data(converted)
    }
}
