import Foundation
import BigInt

struct Base32 {
    static let characters: [Character] = [
        "q", "p", "z", "r", "y", "9", "x", "8",
        "g", "f", "2", "t", "v", "d", "w", "0",
        "s", "3", "j", "n", "5", "4", "k", "h",
        "c", "e", "6", "m", "u", "a", "7", "l"
    ]
    private static let baseNumber: Int = characters.count
    
    static func encode(_ data: Data, interpretedAs5Bit: Bool = true) -> String {
        var result = ""
        switch interpretedAs5Bit {
        case true:
            for value in data {
                result += String(characters[Int(value)])
            }
        case false:
            var value = BigUInt(data)
            while value > 0 {
                let remainder = Int(value % BigUInt(baseNumber))
                value /= BigUInt(baseNumber)
                result = String(characters[remainder]) + result
            }
        }
        return result
    }
    
    static func decode(_ base32: String) -> Data? {
        var total: BigUInt = 0
        
        for character in base32 {
            guard let characterIndex = characters.firstIndex(of: character) else { return nil }
            
            let value = BigUInt(characters.distance(from: characters.startIndex, to: characterIndex))
            total = total * BigUInt(baseNumber) + value
        }
        
        var bytes = [UInt8]()
        while total > 0 {
            let byte = UInt8(total & 0xff)
            bytes.insert(byte, at: 0)
            total >>= 8
        }
        
        let leadingOnes = base32.prefix { $0 == characters.first! }.count
        bytes.insert(contentsOf: Array(repeating: 0, count: leadingOnes), at: 0)
        
        return Data(bytes)
    }
}
