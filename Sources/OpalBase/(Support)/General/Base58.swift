// Base58.swift

import Foundation
import BigInt

struct Base58 {
    static let characters: [Character] = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "A", "B", "C", "D", "E", "F", "G", "H",
        "J", "K", "L", "M", "N",
        "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k",
        "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
    ]
    private static let baseNumber: Int = characters.count
    
    static func encode(_ data: Data) -> String {
        var value = BigUInt(data)
        var result = ""
        while value > 0 {
            let remainder = Int(value % BigUInt(baseNumber))
            value /= BigUInt(baseNumber)
            result = String(characters[remainder]) + result
        }
        
        let leadingZeroBytes = data.prefix { $0 == 0 }.count
        result = String(repeating: characters.first!, count: leadingZeroBytes) + result
        
        return result
    }
    
    static func decode(_ base58: String) -> Data? {
        var total: BigUInt = 0
        
        for character in base58 {
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
        
        let leadingOnes = base58.prefix { $0 == characters.first! }.count
        bytes.insert(contentsOf: Array(repeating: 0, count: leadingOnes), at: 0)
        
        return Data(bytes)
    }
}
