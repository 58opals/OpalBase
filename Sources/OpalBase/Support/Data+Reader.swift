// Data+Reader.swift

import Foundation

extension Data {
    struct Reader {
        let data: Data
        private let startIndex: Data.Index
        private(set) var index: Data.Index
        
        init(_ data: Data, startingAt index: Data.Index? = nil) {
            self.data = data
            self.startIndex = index ?? data.startIndex
            self.index = self.startIndex
        }
        
        var bytesRead: Int {
            data.distance(from: startIndex, to: index)
        }
        
        var remainingData: Data {
            data[index...]
        }
        
        mutating func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type = T.self) throws -> T {
            let (value, nextIndex): (T, Data.Index) = try data.extractValue(from: index)
            index = nextIndex
            return value
        }
        
        mutating func readData(count: Int) throws -> Data {
            guard count >= 0 else { throw Error.negativeReadCount(count) }
            guard let nextIndex = data.index(index, offsetBy: count, limitedBy: data.endIndex) else {
                throw Data.Error.indexOutOfRange
            }
            let slice = data[index..<nextIndex]
            index = nextIndex
            return Data(slice)
        }
        
        mutating func readCompactSize() throws -> CompactSize {
            let (value, size) = try CompactSize.decode(from: data[index...])
            index += size
            return value
        }
        
        mutating func advance(by count: Int) throws {
            guard count >= 0 else { throw Error.negativeAdvance(count) }
            guard let nextIndex = data.index(index, offsetBy: count, limitedBy: data.endIndex) else {
                throw Error.endOfData
            }
            index = nextIndex
        }
        
        enum Error: Swift.Error, Equatable {
            case endOfData
            case negativeAdvance(Int)
            case negativeReadCount(Int)
        }
    }
}
