// String+.swift

import Foundation

extension String {
    func padLeft(to length: Int, with character: Character = "0") -> String {
        switch count < length {
        case true:
            return String(repeatElement(character, count: length - count)) + self
        case false:
            return String(suffix(length))
        }
    }
    
    func convertBitToData() -> Data {
        var bytes = [UInt8]()
        var currentByte: UInt8 = 0
        
        for (index, bit) in self.enumerated() {
            currentByte <<= 1
            if bit == "1" {
                currentByte |= 1
            }
            if index % 8 == 7 {
                bytes.append(currentByte)
                currentByte = 0
            }
        }
        
        if self.count % 8 != 0 {
            currentByte <<= (8 - self.count % 8)
            bytes.append(currentByte)
        }
        return Data(bytes)
    }
}
