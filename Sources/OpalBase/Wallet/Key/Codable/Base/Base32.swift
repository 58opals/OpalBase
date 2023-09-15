// Opal Base by 58 Opals

import Foundation

struct Base32: BaseCodable {
    let alphabets: String = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    
    func encode(_ data: Data) -> String {
        let encodedBytes = Array(data.convertTo5Bit(pad: true))
        var encodedString = ""
        for byte in encodedBytes {
            encodedString += String(alphabets[String.Index.init(utf16Offset: Int(byte), in: alphabets)])
        }
        
        return encodedString
    }
    
    func encode(_ number: Int) -> String {
        var encodedNumberString = ""
        var remainingValue = number
        while remainingValue > 0 {
            encodedNumberString += String(alphabets[String.Index.init(utf16Offset: remainingValue%baseNumber, in: alphabets)])
            remainingValue = remainingValue/baseNumber
        }
        
        while encodedNumberString.count < 8 {
            encodedNumberString += alphabets.prefix(1)
        }
        
        return String(encodedNumberString.reversed())
    }
    
    func decode(_ string: String) -> Data {
        var decodedData = Data()
        var bitAccumulator = 0
        var bits = 0
        for character in string {
            guard let index = alphabets.firstIndex(of: character) else { fatalError() }
            let offset = alphabets.distance(from: alphabets.startIndex, to: index)
            bitAccumulator = (bitAccumulator << 5) | offset
            bits += 5
            while bits >= 8 {
                bits -= 8
                decodedData.append(UInt8((bitAccumulator >> bits) & 0xFF))
            }
        }
        
        return decodedData
    }
}
