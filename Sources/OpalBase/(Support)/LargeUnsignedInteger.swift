// LargeUnsignedInteger.swift

import Foundation

public struct LargeUnsignedInteger: Comparable, Sendable {
    private var words: [UInt32]
    
    static let zero = LargeUnsignedInteger(words: [])
    
    init(_ value: UInt64) {
        if value == 0 {
            self.words = []
        } else {
            let lower = UInt32(value & 0xffff_ffff)
            let upper = UInt32(value >> 32)
            self.words = upper == 0 ? [lower] : [lower, upper]
        }
    }
    
    init(_ data: Data) {
        guard !data.isEmpty else {
            self.words = []
            return
        }
        var values: [UInt32] = []
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
    
    var isZero: Bool {
        words.isEmpty
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
    
    func shiftedLeft(by bits: Int) -> LargeUnsignedInteger {
        guard bits > 0 else { return self }
        precondition(bits % 8 == 0, "Shift must be a multiple of 8.")
        var data = serialize()
        data.append(contentsOf: repeatElement(0, count: bits / 8))
        return LargeUnsignedInteger(data)
    }
    
    func shiftedRight(by bits: Int) -> LargeUnsignedInteger {
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
    
    mutating func add(_ addend: Int) {
        precondition(addend >= 0, "Addend must be non-negative.")
        var carry = UInt64(addend)
        var index = 0
        while carry > 0 {
            if index == words.count {
                words.append(0)
            }
            let sum = UInt64(words[index]) + carry
            words[index] = UInt32(sum & 0xffff_ffff)
            carry = sum >> 32
            index += 1
        }
    }
    
    mutating func multiply(by multiplier: Int) {
        precondition(multiplier >= 0, "Multiplier must be non-negative.")
        guard !words.isEmpty, multiplier > 1 else {
            if multiplier == 0 {
                words = []
            }
            return
        }
        var carry: UInt64 = 0
        for index in words.indices {
            let product = UInt64(words[index]) * UInt64(multiplier) + carry
            words[index] = UInt32(product & 0xffff_ffff)
            carry = product >> 32
        }
        if carry > 0 {
            words.append(UInt32(carry))
        }
    }
    
    mutating func divide(by divisor: Int) -> Int {
        precondition(divisor > 0, "Divisor must be positive.")
        guard !words.isEmpty else { return 0 }
        var remainder: UInt64 = 0
        var quotientWords = Array(repeating: UInt32(0), count: words.count)
        for index in words.indices.reversed() {
            let value = (remainder << 32) + UInt64(words[index])
            let quotient = value / UInt64(divisor)
            remainder = value % UInt64(divisor)
            quotientWords[index] = UInt32(quotient)
        }
        self = LargeUnsignedInteger(words: quotientWords)
        return Int(remainder)
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
