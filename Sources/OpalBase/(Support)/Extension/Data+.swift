import Foundation

extension Data {
    var hexadecimalString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    func convertToBitString() -> String {
        return self.map { String($0, radix: 2).padLeft(to: 8) }.joined()
    }
}

extension Data {
    func extractValue<T: FixedWidthInteger>(from start: Data.Index) -> (value: T, newIndex: Data.Index) {
        let size = MemoryLayout<T>.size
        guard start + size <= self.endIndex else { fatalError("Index out of range") }
        var value: T = 0
        for i in 0..<size {
            value |= T(self[start + i]) << (i * 8)
        }
        let newIndex = start + size
        
        return (T(littleEndian: value), newIndex)
    }
}
