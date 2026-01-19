// Base32.swift

import Foundation

struct Base32 {
    static let characters: [Character] = [
        "q", "p", "z", "r", "y", "9", "x", "8",
        "g", "f", "2", "t", "v", "d", "w", "0",
        "s", "3", "j", "n", "5", "4", "k", "h",
        "c", "e", "6", "m", "u", "a", "7", "l"
    ]
    private static let baseNumber: Int = characters.count
    
    static func encode(_ data: Data, interpretedAs5Bit: Bool) -> String {
        switch interpretedAs5Bit {
        case true:
            var result = String()
            result.reserveCapacity(data.count)
            for value in data {
                result.append(characters[Int(value)])
            }
            return result
        case false:
            var value = BigUInt(data)
            var charactersResult: [Character] = .init()
            charactersResult.reserveCapacity(Swift.max(1, data.count * 2))
            while value > 0 {
                let remainder = Int(value % BigUInt(baseNumber))
                value /= BigUInt(baseNumber)
                charactersResult.append(characters[remainder])
            }
            return String(charactersResult.reversed())
        }
    }
    
    static func decode(_ string: String, interpretedAs5Bit: Bool) throws -> Data {
        var data = Data()
        switch interpretedAs5Bit {
        case true:
            for character in string {
                let normalizedCharacter = try normalizeCharacter(character)
                
                if let index = characters.firstIndex(of: normalizedCharacter) {
                    data.append(UInt8(index))
                } else {
                    throw Error.invalidCharacterFound
                }
            }
        case false:
            var value = BigUInt(0)
            for character in string {
                let normalizedCharacter = try normalizeCharacter(character)
                
                if let index = characters.firstIndex(of: normalizedCharacter) {
                    value = value * BigUInt(baseNumber) + BigUInt(index)
                } else {
                    throw Error.invalidCharacterFound
                }
            }
            data = value.serialize()
        }
        return data
    }
    
    private static func normalizeCharacter(_ character: Character) throws -> Character {
        guard let asciiValue = character.asciiValue else { return character }
        
        switch asciiValue {
        case 0x41...0x5A:
            let normalizedAsciiValue = asciiValue &+ 0x20
            let scalar = UnicodeScalar(normalizedAsciiValue)
            return Character(scalar)
        default:
            return character
        }
    }
}

extension Base32 {
    enum Error: Swift.Error {
        case invalidCharacterFound
    }
}
