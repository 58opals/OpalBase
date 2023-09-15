// Opal Base by 58 Opals

import Foundation
import BigInt

struct Base58: BaseCodable {
    let alphabets = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    var alphabetsBytes: Array<UInt8> { .init(alphabets.utf8) }
    var radix: BigUInt { BigUInt(alphabetsBytes.count) }
    
    func encode(_ data: Data) -> String {
        var answer = [UInt8]()
        var integerBytes = BigUInt(data)

        while integerBytes > 0 {
            let (quotient, remainder) = integerBytes.quotientAndRemainder(dividingBy: self.radix)
            answer.insert(self.alphabetsBytes[Int(remainder)], at: 0)
            integerBytes = quotient
        }
        
        let prefix = Array(data.prefix { $0 == 0 }).map { _ in self.alphabetsBytes[0] }
        answer.insert(contentsOf: prefix, at: 0)

        return String(bytes: answer, encoding: .utf8)!
    }
    
    func encode(_ string: String) -> String {
        return encode(string.data(using: .utf8)!)
    }
    
    func decode(_ string: String) -> Data {
        var answer = BigUInt(0)
        var i = BigUInt(1)

        let stringBytes = [UInt8](string.utf8)
        for character in stringBytes.reversed() {
            guard let alphabetIndex = self.alphabetsBytes.firstIndex(of: character) else { fatalError() }
            answer += (i * BigUInt(alphabetIndex))
            i *= self.radix
        }

        let bytes = answer.serialize()
        let leadingOnes = stringBytes.prefix(while: { value in value == self.alphabetsBytes[0]})
        let leadingZeros = Data(repeating: 0, count: leadingOnes.count)
        return leadingZeros + bytes
    }
    
    func decode(_ string: String) -> String {
        return String(decoding: decode(string), as: UTF8.self)
    }
}
