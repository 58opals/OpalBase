// RIPEMD160.swift

import Foundation

struct RIPEMD160 {
    private var hashState: (UInt32, UInt32, UInt32, UInt32, UInt32)
    private var messageBuffer: Data
    private var processedBytesCount: Int64 // Total number of bytes processed.

    public init() {
        hashState = (0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0)
        messageBuffer = Data()
        processedBytesCount = 0
    }
}

extension RIPEMD160 {
    static func hash(_ data: Data) -> Data {
        var ripemd = Self()
        ripemd.update(data: data)
        return ripemd.finalize()
    }
}

// MARK: - RIPEMD-160 Hashing
extension RIPEMD160 {
    mutating func update(data: Data) {
        var words = [UInt32](repeating: 0, count: 16)
        var currentPosition = data.startIndex
        var remainingLength = data.count

        // Process remaining bytes from the last call
        if messageBuffer.count > 0 && messageBuffer.count + remainingLength >= 64 {
            let chunkSize = 64 - messageBuffer.count
            messageBuffer.append(data[..<chunkSize])
            words.withUnsafeMutableBytes {
                _ = messageBuffer.copyBytes(to: $0)
            }
            compress(words)
            currentPosition += chunkSize
            remainingLength -= chunkSize
        }

        // Process 64 byte chunks
        while remainingLength >= 64 {
            words.withUnsafeMutableBytes {
                _ = data[currentPosition..<currentPosition+64].copyBytes(to: $0)
            }
            compress(words)
            currentPosition += 64
            remainingLength -= 64
        }

        // Save remaining unprocessed bytes
        messageBuffer = data[currentPosition...]
        processedBytesCount += Int64(data.count)
    }

    public mutating func finalize() -> Data {
        var words = [UInt32](repeating: 0, count: 16)
        // Append the bit m_n == 1
        messageBuffer.append(0x80)
        words.withUnsafeMutableBytes {
            _ = messageBuffer.copyBytes(to: $0)
        }

        if (processedBytesCount & 63) > 55 {
            // Length goes to the next block
            compress(words)
            words = [UInt32](repeating: 0, count: 16)
        }

        // Append length in bits
        let lowerWord = UInt32(truncatingIfNeeded: processedBytesCount)
        let upperWord = UInt32(UInt64(processedBytesCount) >> 32)
        words[14] = lowerWord << 3
        words[15] = (lowerWord >> 29) | (upperWord << 3)
        compress(words)

        messageBuffer = Data()
        let result = [hashState.0, hashState.1, hashState.2, hashState.3, hashState.4]
        return result.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Helpers
fileprivate extension RIPEMD160 {
    mutating func compress(_ X: UnsafePointer<UInt32>) {
        func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 {
            (x << n) | ( x >> (32 - n))
        }

        func F(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            x ^ y ^ z
        }

        func G(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            (x & y) | (~x & z)
        }

        func H(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            (x | ~y) ^ z
        }

        func I(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            (x & z) | (y & ~z)
        }

        func J(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            x ^ (y | ~z)
        }

        func FF(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ F(b, c, d) &+ x
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func GG(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ G(b, c, d) &+ x &+ 0x5a827999
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func HH(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ H(b, c, d) &+ x &+ 0x6ed9eba1
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func II(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ I(b, c, d) &+ x &+ 0x8f1bbcdc
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func JJ(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ J(b, c, d) &+ x &+ 0xa953fd4e
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func FFF(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ F(b, c, d) &+ x
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func GGG(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ G(b, c, d) &+ x &+ 0x7a6d76e9
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func HHH(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ H(b, c, d) &+ x &+ 0x6d703ef3
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func III(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ I(b, c, d) &+ x &+ 0x5c4dd124
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        func JJJ(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ J(b, c, d) &+ x &+ 0x50a28be6
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }

        var (a1, b1, c1, d1, e1) = hashState
        var (a2, b2, c2, d2, e2) = hashState

        // Round 1
        FF(&a1, b1, &c1, d1, e1, X[ 0], 11)
        FF(&e1, a1, &b1, c1, d1, X[ 1], 14)
        FF(&d1, e1, &a1, b1, c1, X[ 2], 15)
        FF(&c1, d1, &e1, a1, b1, X[ 3], 12)
        FF(&b1, c1, &d1, e1, a1, X[ 4],  5)
        FF(&a1, b1, &c1, d1, e1, X[ 5],  8)
        FF(&e1, a1, &b1, c1, d1, X[ 6],  7)
        FF(&d1, e1, &a1, b1, c1, X[ 7],  9)
        FF(&c1, d1, &e1, a1, b1, X[ 8], 11)
        FF(&b1, c1, &d1, e1, a1, X[ 9], 13)
        FF(&a1, b1, &c1, d1, e1, X[10], 14)
        FF(&e1, a1, &b1, c1, d1, X[11], 15)
        FF(&d1, e1, &a1, b1, c1, X[12],  6)
        FF(&c1, d1, &e1, a1, b1, X[13],  7)
        FF(&b1, c1, &d1, e1, a1, X[14],  9)
        FF(&a1, b1, &c1, d1, e1, X[15],  8)

        // Round 2
        GG(&e1, a1, &b1, c1, d1, X[ 7],  7)
        GG(&d1, e1, &a1, b1, c1, X[ 4],  6)
        GG(&c1, d1, &e1, a1, b1, X[13],  8)
        GG(&b1, c1, &d1, e1, a1, X[ 1], 13)
        GG(&a1, b1, &c1, d1, e1, X[10], 11)
        GG(&e1, a1, &b1, c1, d1, X[ 6],  9)
        GG(&d1, e1, &a1, b1, c1, X[15],  7)
        GG(&c1, d1, &e1, a1, b1, X[ 3], 15)
        GG(&b1, c1, &d1, e1, a1, X[12],  7)
        GG(&a1, b1, &c1, d1, e1, X[ 0], 12)
        GG(&e1, a1, &b1, c1, d1, X[ 9], 15)
        GG(&d1, e1, &a1, b1, c1, X[ 5],  9)
        GG(&c1, d1, &e1, a1, b1, X[ 2], 11)
        GG(&b1, c1, &d1, e1, a1, X[14],  7)
        GG(&a1, b1, &c1, d1, e1, X[11], 13)
        GG(&e1, a1, &b1, c1, d1, X[ 8], 12)

        // Round 3
        HH(&d1, e1, &a1, b1, c1, X[ 3], 11)
        HH(&c1, d1, &e1, a1, b1, X[10], 13)
        HH(&b1, c1, &d1, e1, a1, X[14],  6)
        HH(&a1, b1, &c1, d1, e1, X[ 4],  7)
        HH(&e1, a1, &b1, c1, d1, X[ 9], 14)
        HH(&d1, e1, &a1, b1, c1, X[15],  9)
        HH(&c1, d1, &e1, a1, b1, X[ 8], 13)
        HH(&b1, c1, &d1, e1, a1, X[ 1], 15)
        HH(&a1, b1, &c1, d1, e1, X[ 2], 14)
        HH(&e1, a1, &b1, c1, d1, X[ 7],  8)
        HH(&d1, e1, &a1, b1, c1, X[ 0], 13)
        HH(&c1, d1, &e1, a1, b1, X[ 6],  6)
        HH(&b1, c1, &d1, e1, a1, X[13],  5)
        HH(&a1, b1, &c1, d1, e1, X[11], 12)
        HH(&e1, a1, &b1, c1, d1, X[ 5],  7)
        HH(&d1, e1, &a1, b1, c1, X[12],  5)

        // Round 4
        II(&c1, d1, &e1, a1, b1, X[ 1], 11)
        II(&b1, c1, &d1, e1, a1, X[ 9], 12)
        II(&a1, b1, &c1, d1, e1, X[11], 14)
        II(&e1, a1, &b1, c1, d1, X[10], 15)
        II(&d1, e1, &a1, b1, c1, X[ 0], 14)
        II(&c1, d1, &e1, a1, b1, X[ 8], 15)
        II(&b1, c1, &d1, e1, a1, X[12],  9)
        II(&a1, b1, &c1, d1, e1, X[ 4],  8)
        II(&e1, a1, &b1, c1, d1, X[13],  9)
        II(&d1, e1, &a1, b1, c1, X[ 3], 14)
        II(&c1, d1, &e1, a1, b1, X[ 7],  5)
        II(&b1, c1, &d1, e1, a1, X[15],  6)
        II(&a1, b1, &c1, d1, e1, X[14],  8)
        II(&e1, a1, &b1, c1, d1, X[ 5],  6)
        II(&d1, e1, &a1, b1, c1, X[ 6],  5)
        II(&c1, d1, &e1, a1, b1, X[ 2], 12)

        // Round 5
        JJ(&b1, c1, &d1, e1, a1, X[ 4],  9)
        JJ(&a1, b1, &c1, d1, e1, X[ 0], 15)
        JJ(&e1, a1, &b1, c1, d1, X[ 5],  5)
        JJ(&d1, e1, &a1, b1, c1, X[ 9], 11)
        JJ(&c1, d1, &e1, a1, b1, X[ 7],  6)
        JJ(&b1, c1, &d1, e1, a1, X[12],  8)
        JJ(&a1, b1, &c1, d1, e1, X[ 2], 13)
        JJ(&e1, a1, &b1, c1, d1, X[10], 12)
        JJ(&d1, e1, &a1, b1, c1, X[14],  5)
        JJ(&c1, d1, &e1, a1, b1, X[ 1], 12)
        JJ(&b1, c1, &d1, e1, a1, X[ 3], 13)
        JJ(&a1, b1, &c1, d1, e1, X[ 8], 14)
        JJ(&e1, a1, &b1, c1, d1, X[11], 11)
        JJ(&d1, e1, &a1, b1, c1, X[ 6],  8)
        JJ(&c1, d1, &e1, a1, b1, X[15],  5)
        JJ(&b1, c1, &d1, e1, a1, X[13],  6)

        // Parallel round 1
        JJJ(&a2, b2, &c2, d2, e2, X[ 5],  8)
        JJJ(&e2, a2, &b2, c2, d2, X[14],  9)
        JJJ(&d2, e2, &a2, b2, c2, X[ 7],  9)
        JJJ(&c2, d2, &e2, a2, b2, X[ 0], 11)
        JJJ(&b2, c2, &d2, e2, a2, X[ 9], 13)
        JJJ(&a2, b2, &c2, d2, e2, X[ 2], 15)
        JJJ(&e2, a2, &b2, c2, d2, X[11], 15)
        JJJ(&d2, e2, &a2, b2, c2, X[ 4],  5)
        JJJ(&c2, d2, &e2, a2, b2, X[13],  7)
        JJJ(&b2, c2, &d2, e2, a2, X[ 6],  7)
        JJJ(&a2, b2, &c2, d2, e2, X[15],  8)
        JJJ(&e2, a2, &b2, c2, d2, X[ 8], 11)
        JJJ(&d2, e2, &a2, b2, c2, X[ 1], 14)
        JJJ(&c2, d2, &e2, a2, b2, X[10], 14)
        JJJ(&b2, c2, &d2, e2, a2, X[ 3], 12)
        JJJ(&a2, b2, &c2, d2, e2, X[12],  6)

        // Parallel round 2
        III(&e2, a2, &b2, c2, d2, X[ 6],  9)
        III(&d2, e2, &a2, b2, c2, X[11], 13)
        III(&c2, d2, &e2, a2, b2, X[ 3], 15)
        III(&b2, c2, &d2, e2, a2, X[ 7],  7)
        III(&a2, b2, &c2, d2, e2, X[ 0], 12)
        III(&e2, a2, &b2, c2, d2, X[13],  8)
        III(&d2, e2, &a2, b2, c2, X[ 5],  9)
        III(&c2, d2, &e2, a2, b2, X[10], 11)
        III(&b2, c2, &d2, e2, a2, X[14],  7)
        III(&a2, b2, &c2, d2, e2, X[15],  7)
        III(&e2, a2, &b2, c2, d2, X[ 8], 12)
        III(&d2, e2, &a2, b2, c2, X[12],  7)
        III(&c2, d2, &e2, a2, b2, X[ 4],  6)
        III(&b2, c2, &d2, e2, a2, X[ 9], 15)
        III(&a2, b2, &c2, d2, e2, X[ 1], 13)
        III(&e2, a2, &b2, c2, d2, X[ 2], 11)

        // Parallel round 3
        HHH(&d2, e2, &a2, b2, c2, X[15],  9)
        HHH(&c2, d2, &e2, a2, b2, X[ 5],  7)
        HHH(&b2, c2, &d2, e2, a2, X[ 1], 15)
        HHH(&a2, b2, &c2, d2, e2, X[ 3], 11)
        HHH(&e2, a2, &b2, c2, d2, X[ 7],  8)
        HHH(&d2, e2, &a2, b2, c2, X[14],  6)
        HHH(&c2, d2, &e2, a2, b2, X[ 6],  6)
        HHH(&b2, c2, &d2, e2, a2, X[ 9], 14)
        HHH(&a2, b2, &c2, d2, e2, X[11], 12)
        HHH(&e2, a2, &b2, c2, d2, X[ 8], 13)
        HHH(&d2, e2, &a2, b2, c2, X[12],  5)
        HHH(&c2, d2, &e2, a2, b2, X[ 2], 14)
        HHH(&b2, c2, &d2, e2, a2, X[10], 13)
        HHH(&a2, b2, &c2, d2, e2, X[ 0], 13)
        HHH(&e2, a2, &b2, c2, d2, X[ 4],  7)
        HHH(&d2, e2, &a2, b2, c2, X[13],  5)

        // Parallel round 4
        GGG(&c2, d2, &e2, a2, b2, X[ 8], 15)
        GGG(&b2, c2, &d2, e2, a2, X[ 6],  5)
        GGG(&a2, b2, &c2, d2, e2, X[ 4],  8)
        GGG(&e2, a2, &b2, c2, d2, X[ 1], 11)
        GGG(&d2, e2, &a2, b2, c2, X[ 3], 14)
        GGG(&c2, d2, &e2, a2, b2, X[11], 14)
        GGG(&b2, c2, &d2, e2, a2, X[15],  6)
        GGG(&a2, b2, &c2, d2, e2, X[ 0], 14)
        GGG(&e2, a2, &b2, c2, d2, X[ 5],  6)
        GGG(&d2, e2, &a2, b2, c2, X[12],  9)
        GGG(&c2, d2, &e2, a2, b2, X[ 2], 12)
        GGG(&b2, c2, &d2, e2, a2, X[13],  9)
        GGG(&a2, b2, &c2, d2, e2, X[ 9], 12)
        GGG(&e2, a2, &b2, c2, d2, X[ 7],  5)
        GGG(&d2, e2, &a2, b2, c2, X[10], 15)
        GGG(&c2, d2, &e2, a2, b2, X[14],  8)

        // Parallel round 5
        FFF(&b2, c2, &d2, e2, a2, X[12] ,  8)
        FFF(&a2, b2, &c2, d2, e2, X[15] ,  5)
        FFF(&e2, a2, &b2, c2, d2, X[10] , 12)
        FFF(&d2, e2, &a2, b2, c2, X[ 4] ,  9)
        FFF(&c2, d2, &e2, a2, b2, X[ 1] , 12)
        FFF(&b2, c2, &d2, e2, a2, X[ 5] ,  5)
        FFF(&a2, b2, &c2, d2, e2, X[ 8] , 14)
        FFF(&e2, a2, &b2, c2, d2, X[ 7] ,  6)
        FFF(&d2, e2, &a2, b2, c2, X[ 6] ,  8)
        FFF(&c2, d2, &e2, a2, b2, X[ 2] , 13)
        FFF(&b2, c2, &d2, e2, a2, X[13] ,  6)
        FFF(&a2, b2, &c2, d2, e2, X[14] ,  5)
        FFF(&e2, a2, &b2, c2, d2, X[ 0] , 15)
        FFF(&d2, e2, &a2, b2, c2, X[ 3] , 13)
        FFF(&c2, d2, &e2, a2, b2, X[ 9] , 11)
        FFF(&b2, c2, &d2, e2, a2, X[11] , 11)

        // Combine results
        hashState = (
            hashState.1 &+ c1 &+ d2,
            hashState.2 &+ d1 &+ e2,
            hashState.3 &+ e1 &+ a2,
            hashState.4 &+ a1 &+ b2,
            hashState.0 &+ b1 &+ c2
        )
    }
}
