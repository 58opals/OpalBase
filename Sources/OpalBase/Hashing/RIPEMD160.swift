// RIPEMD160.swift

import Foundation

struct RIPEMD160 {
    var hashState: (UInt32, UInt32, UInt32, UInt32, UInt32)
    var messageBuffer: Data
    var processedBytesCount: Int64 // Total number of bytes processed.

    init() {
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
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 16) { words in
            words.initialize(repeating: 0)
            var currentPosition = data.startIndex
            var remainingLength = data.count

            // Process remaining bytes from the last call
            if messageBuffer.count > 0 && messageBuffer.count + remainingLength >= 64 {
                let chunkSize = 64 - messageBuffer.count
                messageBuffer.append(data[..<chunkSize])
                guard let baseAddress = words.baseAddress else { return }
                let wordBytes = UnsafeMutableRawBufferPointer(start: baseAddress, count: 64)
                _ = messageBuffer.copyBytes(to: wordBytes)
                compress(baseAddress)
                currentPosition += chunkSize
                remainingLength -= chunkSize
            }
            // Process 64 byte chunks
            while remainingLength >= 64 {
                guard let baseAddress = words.baseAddress else { return }
                let wordBytes = UnsafeMutableRawBufferPointer(start: baseAddress, count: 64)
                _ = data[currentPosition..<currentPosition+64].copyBytes(to: wordBytes)
                compress(baseAddress)
                currentPosition += 64
                remainingLength -= 64
            }
            // Save remaining unprocessed bytes
            messageBuffer = data[currentPosition...]
            processedBytesCount += Int64(data.count)
        }
    }

    mutating func finalize() -> Data {
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 16) { words in
            words.initialize(repeating: 0)
            // Append the bit m_n == 1
            messageBuffer.append(0x80)
            guard let baseAddress = words.baseAddress else { return Data() }
            let wordBytes = UnsafeMutableRawBufferPointer(start: baseAddress, count: 64)
            _ = messageBuffer.copyBytes(to: wordBytes)

            if (processedBytesCount & 63) > 55 {
                // Length goes to the next block
                compress(baseAddress)
                words.update(repeating: 0)
            }

            // Append length in bits
            let lowerWord = UInt32(truncatingIfNeeded: processedBytesCount)
            let upperWord = UInt32(UInt64(processedBytesCount) >> 32)
            words[14] = lowerWord << 3
            words[15] = (lowerWord >> 29) | (upperWord << 3)
            compress(baseAddress)

            messageBuffer = Data()
            let result = [hashState.0, hashState.1, hashState.2, hashState.3, hashState.4]
            return result.withUnsafeBytes { Data($0) }
        }
    }
}
