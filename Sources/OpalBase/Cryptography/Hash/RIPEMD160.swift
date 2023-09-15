// Opal Base by 58 Opals

import Foundation

struct RIPEMD160 {
    private var hashBuffer: (UInt32, UInt32, UInt32, UInt32, UInt32)
    private var dataBuffer: Data
    private var processedByteCount: Int64
    
    public init() {
        hashBuffer = (0x67452301,
                      0xefcdab89,
                      0x98badcfe,
                      0x10325476,
                      0xc3d2e1f0)
        dataBuffer = Data()
        processedByteCount = 0
    }
    
    mutating func updateHash(with data: Data) {
        var messageBlock = [UInt32](repeating: 0, count: 16)
        var currentPosition = data.startIndex
        var remainingLength = data.count
        
        if dataBuffer.count > 0 && dataBuffer.count + remainingLength >= 64 {
            let bytesToFillBuffer = 64 - dataBuffer.count
            dataBuffer.append(data[..<bytesToFillBuffer])
            messageBlock.withUnsafeMutableBytes {
                _ = dataBuffer.copyBytes(to: $0)
            }
            compressBlock(messageBlock)
            currentPosition += bytesToFillBuffer
            remainingLength -= bytesToFillBuffer
        }
        
        while remainingLength >= 64 {
            messageBlock.withUnsafeMutableBytes {
                _ = data[currentPosition..<currentPosition+64].copyBytes(to: $0)
            }
            compressBlock(messageBlock)
            currentPosition += 64
            remainingLength -= 64
        }
        
        dataBuffer = data[currentPosition...]
        processedByteCount += Int64(data.count)
    }
    
    mutating func finalizeHash() -> Data {
        var messageBlock = [UInt32](repeating: 0, count: 16)
        dataBuffer.append(0x80)
        messageBlock.withUnsafeMutableBytes {
            _ = dataBuffer.copyBytes(to: $0)
        }
        
        if (processedByteCount & 63) > 55 {
            compressBlock(messageBlock)
            messageBlock = [UInt32](repeating: 0, count: 16)
        }
        
        let lowOrderLength = UInt32(truncatingIfNeeded: processedByteCount)
        let highOrderLength = UInt32(UInt64(processedByteCount) >> 32)
        messageBlock[14] = lowOrderLength << 3
        messageBlock[15] = (lowOrderLength >> 29) | (highOrderLength << 3)
        compressBlock(messageBlock)
        
        dataBuffer = Data()
        let finalHash = [hashBuffer.0, hashBuffer.1, hashBuffer.2, hashBuffer.3, hashBuffer.4]
        return finalHash.withUnsafeBytes { Data($0) }
    }
    
    private mutating func compressBlock(_ messageBlock: UnsafePointer<UInt32>) {
        func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 {
            return (x << n) | ( x >> (32 - n))
        }
        
        func basicRound(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            return x ^ y ^ z
        }
        
        func andRound(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            return (x & y) | (~x & z)
        }
        
        func xorRound(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            return (x | ~y) ^ z
        }
        
        func orRound(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            return (x & z) | (y & ~z)
        }
        
        func complexRound(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            return x ^ (y | ~z)
        }
        
        func basicRoundTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ basicRound(b, c, d) &+ x
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func andRoundTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ andRound(b, c, d) &+ x &+ 0x5a827999
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func xorRoundTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ xorRound(b, c, d) &+ x &+ 0x6ed9eba1
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func orRoundTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ orRound(b, c, d) &+ x &+ 0x8f1bbcdc
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func complexRoundTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ complexRound(b, c, d) &+ x &+ 0xa953fd4e
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func basicRoundAltTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ basicRound(b, c, d) &+ x
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func andRoundAltTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ andRound(b, c, d) &+ x &+ 0x7a6d76e9
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func xorRoundAltTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ xorRound(b, c, d) &+ x &+ 0x6d703ef3
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func orRoundAltTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ orRound(b, c, d) &+ x &+ 0x5c4dd124
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        func complexRoundAltTransform(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
            a = a &+ complexRound(b, c, d) &+ x &+ 0x50a28be6
            a = rotateLeft(a, s) &+ e
            c = rotateLeft(c, 10)
        }
        
        var (aa, bb, cc, dd, ee) = hashBuffer
        var (aaa, bbb, ccc, ddd, eee) = hashBuffer
        
        basicRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 0], 11)
        basicRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 1], 14)
        basicRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 2], 15)
        basicRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 3], 12)
        basicRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 4],  5)
        basicRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 5],  8)
        basicRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 6],  7)
        basicRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 7],  9)
        basicRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 8], 11)
        basicRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 9], 13)
        basicRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[10], 14)
        basicRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[11], 15)
        basicRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[12],  6)
        basicRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[13],  7)
        basicRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[14],  9)
        basicRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[15],  8)
        
        andRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 7],  7)
        andRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 4],  6)
        andRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[13],  8)
        andRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 1], 13)
        andRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[10], 11)
        andRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 6],  9)
        andRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[15],  7)
        andRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 3], 15)
        andRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[12],  7)
        andRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 0], 12)
        andRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 9], 15)
        andRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 5],  9)
        andRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 2], 11)
        andRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[14],  7)
        andRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[11], 13)
        andRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 8], 12)
        
        xorRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 3], 11)
        xorRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[10], 13)
        xorRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[14],  6)
        xorRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 4],  7)
        xorRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 9], 14)
        xorRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[15],  9)
        xorRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 8], 13)
        xorRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 1], 15)
        xorRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 2], 14)
        xorRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 7],  8)
        xorRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 0], 13)
        xorRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 6],  6)
        xorRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[13],  5)
        xorRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[11], 12)
        xorRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 5],  7)
        xorRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[12],  5)
        
        orRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 1], 11)
        orRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 9], 12)
        orRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[11], 14)
        orRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[10], 15)
        orRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 0], 14)
        orRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 8], 15)
        orRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[12],  9)
        orRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 4],  8)
        orRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[13],  9)
        orRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 3], 14)
        orRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 7],  5)
        orRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[15],  6)
        orRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[14],  8)
        orRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 5],  6)
        orRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 6],  5)
        orRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 2], 12)
        
        complexRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 4],  9)
        complexRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 0], 15)
        complexRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[ 5],  5)
        complexRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 9], 11)
        complexRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 7],  6)
        complexRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[12],  8)
        complexRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 2], 13)
        complexRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[10], 12)
        complexRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[14],  5)
        complexRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[ 1], 12)
        complexRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[ 3], 13)
        complexRoundTransform(&aa, bb, &cc, dd, ee, messageBlock[ 8], 14)
        complexRoundTransform(&ee, aa, &bb, cc, dd, messageBlock[11], 11)
        complexRoundTransform(&dd, ee, &aa, bb, cc, messageBlock[ 6],  8)
        complexRoundTransform(&cc, dd, &ee, aa, bb, messageBlock[15],  5)
        complexRoundTransform(&bb, cc, &dd, ee, aa, messageBlock[13],  6)
        
        complexRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 5],  8)
        complexRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[14],  9)
        complexRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 7],  9)
        complexRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 0], 11)
        complexRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 9], 13)
        complexRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 2], 15)
        complexRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[11], 15)
        complexRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 4],  5)
        complexRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[13],  7)
        complexRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 6],  7)
        complexRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[15],  8)
        complexRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 8], 11)
        complexRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 1], 14)
        complexRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[10], 14)
        complexRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 3], 12)
        complexRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[12],  6)
        
        orRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 6],  9)
        orRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[11], 13)
        orRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 3], 15)
        orRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 7],  7)
        orRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 0], 12)
        orRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[13],  8)
        orRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 5],  9)
        orRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[10], 11)
        orRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[14],  7)
        orRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[15],  7)
        orRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 8], 12)
        orRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[12],  7)
        orRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 4],  6)
        orRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 9], 15)
        orRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 1], 13)
        orRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 2], 11)
        
        xorRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[15],  9)
        xorRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 5],  7)
        xorRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 1], 15)
        xorRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 3], 11)
        xorRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 7],  8)
        xorRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[14],  6)
        xorRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 6],  6)
        xorRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 9], 14)
        xorRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[11], 12)
        xorRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 8], 13)
        xorRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[12],  5)
        xorRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 2], 14)
        xorRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[10], 13)
        xorRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 0], 13)
        xorRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 4],  7)
        xorRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[13],  5)
        
        andRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 8], 15)
        andRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 6],  5)
        andRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 4],  8)
        andRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 1], 11)
        andRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 3], 14)
        andRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[11], 14)
        andRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[15],  6)
        andRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 0], 14)
        andRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 5],  6)
        andRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[12],  9)
        andRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 2], 12)
        andRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[13],  9)
        andRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 9], 12)
        andRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 7],  5)
        andRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[10], 15)
        andRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[14],  8)
        
        basicRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[12] ,  8)
        basicRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[15] ,  5)
        basicRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[10] , 12)
        basicRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 4] ,  9)
        basicRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 1] , 12)
        basicRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[ 5] ,  5)
        basicRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[ 8] , 14)
        basicRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 7] ,  6)
        basicRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 6] ,  8)
        basicRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 2] , 13)
        basicRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[13] ,  6)
        basicRoundAltTransform(&aaa, bbb, &ccc, ddd, eee, messageBlock[14] ,  5)
        basicRoundAltTransform(&eee, aaa, &bbb, ccc, ddd, messageBlock[ 0] , 15)
        basicRoundAltTransform(&ddd, eee, &aaa, bbb, ccc, messageBlock[ 3] , 13)
        basicRoundAltTransform(&ccc, ddd, &eee, aaa, bbb, messageBlock[ 9] , 11)
        basicRoundAltTransform(&bbb, ccc, &ddd, eee, aaa, messageBlock[11] , 11)
        
        hashBuffer = (hashBuffer.1 &+ cc &+ ddd,
                    hashBuffer.2 &+ dd &+ eee,
                    hashBuffer.3 &+ ee &+ aaa,
                    hashBuffer.4 &+ aa &+ bbb,
                    hashBuffer.0 &+ bb &+ ccc)
    }
}

extension RIPEMD160 {
    static func hmac(key: Data, message: Data) -> Data {
        var key = key
        key.count = 64

        let outerPaddedKey = Data(key.map { $0 ^ 0x5c })
        let innerPaddedKey = Data(key.map { $0 ^ 0x36 })

        var innerHashInstance = RIPEMD160()
        innerHashInstance.updateHash(with: innerPaddedKey)
        innerHashInstance.updateHash(with: message)

        var outerHashInstance = RIPEMD160()
        outerHashInstance.updateHash(with: outerPaddedKey)
        outerHashInstance.updateHash(with: innerHashInstance.finalizeHash())

        return outerHashInstance.finalizeHash()
    }
    
    static func hmac(key: Data, message: String) -> Data {
        return RIPEMD160.hmac(key: key, message: message.data(using: .utf8)!)
    }
    
    static func hmac(key: String, message: String) -> Data {
        return RIPEMD160.hmac(key: key.data(using: .utf8)!, message: message)
    }
    
    static func hmac(key: String, message: Data) -> Data {
        return RIPEMD160.hmac(key: key.data(using: .utf8)!, message: message)
    }
}

extension RIPEMD160 {
    static func hash(_ inputData: Data) -> Data {
        var hashInstance = RIPEMD160()
        hashInstance.updateHash(with: inputData)
        return hashInstance.finalizeHash()
    }
    
    static func hash(_ message: String) -> Data {
        return RIPEMD160.hash(message.data(using: .utf8)!)
    }
}
