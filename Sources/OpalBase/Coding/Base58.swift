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
        var charactersResult: [Character] = .init()
        charactersResult.reserveCapacity(Swift.max(1, data.count * 2))
        while value > 0 {
            let remainder = Int(value % BigUInt(baseNumber))
            value /= BigUInt(baseNumber)
            charactersResult.append(characters[remainder])
        }
        
        let leadingZeroBytes = data.prefix { $0 == 0 }.count
        if leadingZeroBytes > 0 {
            charactersResult.append(contentsOf: repeatElement(characters.first!, count: leadingZeroBytes))
        }
        
        return String(charactersResult.reversed())
    }
    
    static func decode(_ base58: String) -> Data? {
        var total: BigUInt = 0
        
        for character in base58 {
            guard let characterIndex = characters.firstIndex(of: character) else { return nil }
            
            let value = BigUInt(characters.distance(from: characters.startIndex, to: characterIndex))
            total = total * BigUInt(baseNumber) + value
        }
        
        var bytes: [UInt8] = .init()
        while total > 0 {
            bytes.append(UInt8(total & 0xff))
            total >>= 8
        }
        bytes.reverse()
        
        let leadingOnes = base58.prefix { $0 == characters.first! }.count
        if leadingOnes > 0 {
            var prefixed: [UInt8] = .init(repeating: 0, count: leadingOnes)
            prefixed.append(contentsOf: bytes)
            return Data(prefixed)
        }
        
        return Data(bytes)
    }
}
