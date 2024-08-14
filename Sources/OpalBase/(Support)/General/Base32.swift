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
    
    static func encode(_ data: Data, interpretedAs5Bit: Bool) -> String {
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
    
    static func decode(_ string: String, interpretedAs5Bit: Bool) throws -> Data {
         var data = Data()
         switch interpretedAs5Bit {
         case true:
             for char in string {
                 if let index = characters.firstIndex(of: char) {
                     data.append(UInt8(index))
                 } else {
                     throw Error.invalidCharacterFound
                 }
             }
         case false:
             var value = BigUInt(0)
             for char in string {
                 if let index = characters.firstIndex(of: char) {
                     value = value * BigUInt(baseNumber) + BigUInt(index)
                 } else {
                     throw Error.invalidCharacterFound
                 }
             }
             data = value.serialize()
         }
         return data
     }
}
