// LargeUnsignedInteger.swift

import Foundation

struct LargeUnsignedInteger: Comparable, Sendable {
    private var words: [UInt32]
    
    static let zero = LargeUnsignedInteger(words: .init())
    
    init(_ value: UInt64) {
        if value == 0 {
            self.words = .init()
        } else {
            let lower = UInt32(value & 0xffff_ffff)
            let upper = UInt32(value >> 32)
            self.words = upper == 0 ? [lower] : [lower, upper]
        }
    }
    
    init(_ data: Data) {
        guard !data.isEmpty else {
            self.words = .init()
            return
        }
        var values: [UInt32] = .init()
        values.reserveCapacity((data.count + 3) / 4)
        var index = data.count
        while index > 0 {
            let start = Swift.max(0, index - 4)
            let chunk = data[start..<index]
            var value: UInt32 = 0
            for byte in chunk {
                value = (value << 8) | UInt32(byte)
            }
            values.append(value)
            index = start
        }
        self.words = values
        normalize()
    }
    
    func serialize() -> Data {
        guard !words.isEmpty else { return Data() }
        var data = Data()
        for (index, word) in words.reversed().enumerated() {
            var bytes: [UInt8] = [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff)
            ]
            if index == 0 {
                while bytes.first == 0 && bytes.count > 1 {
                    bytes.removeFirst()
                }
            }
            data.append(contentsOf: bytes)
        }
        return data
    }
    
    func shiftLeft(by bits: Int) -> LargeUnsignedInteger {
        guard bits > 0 else { return self }
        precondition(bits % 8 == 0, "Shift must be a multiple of 8.")
        var data = serialize()
        data.append(contentsOf: repeatElement(0, count: bits / 8))
        return LargeUnsignedInteger(data)
    }
    
    func shiftRight(by bits: Int) -> LargeUnsignedInteger {
        guard bits > 0 else { return self }
        precondition(bits % 8 == 0, "Shift must be a multiple of 8.")
        var data = serialize()
        let bytesToRemove = bits / 8
        guard bytesToRemove < data.count else { return .zero }
        data.removeLast(bytesToRemove)
        return LargeUnsignedInteger(data)
    }
    
    public static func < (lhs: LargeUnsignedInteger, rhs: LargeUnsignedInteger) -> Bool {
        if lhs.words.count != rhs.words.count {
            return lhs.words.count < rhs.words.count
        }
        for (leftWord, rightWord) in zip(lhs.words.reversed(), rhs.words.reversed()) {
            if leftWord != rightWord {
                return leftWord < rightWord
            }
        }
        return false
    }

    private init(words: [UInt32]) {
        self.words = words
        normalize()
    }
    
    private mutating func normalize() {
        while let last = words.last, last == 0 {
            words.removeLast()
        }
    }
}
