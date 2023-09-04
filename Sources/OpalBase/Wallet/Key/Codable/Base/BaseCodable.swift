// Opal Base by 58 Opals

import Foundation

protocol BaseCodable {
    var baseNumber: Int { get }
    var alphabets: String { get }
    
    func encode(_ data: Data) -> String
    func decode(_ string: String) -> Data
}

extension BaseCodable {
    var baseNumber: Int { self.alphabets.count }
}

extension BaseCodable {
    func removeLeadingZero(from data: Data) -> Data {
        var numberOfLeadingZero = 0
        for byte in data {
            guard byte == 0 else { break }
            numberOfLeadingZero += 1
        }
        
        return data.dropFirst(numberOfLeadingZero)
    }
}
