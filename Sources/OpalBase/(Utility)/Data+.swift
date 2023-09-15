// Opal Base by 58 Opals

import Foundation

extension Data {
    enum Bit: UInt8, CustomStringConvertible {
        case zero = 0, one = 1
        
        var description: String {
            switch self {
            case .zero: return "0"
            case .one: return "1"
            }
        }
    }
    
    var bits: Array<Bit> {
        let bytes = Array(self)
        var bitsArray: Array<Bit> = .init()
        
        for byte in bytes {
            var shiftedByte = byte
            var bits: Array<Bit> = .init(repeating: .zero, count: 8)
            for index in 0..<8 {
                let bit = shiftedByte & 0x01
                if bit != 0 { bits[index] = .one }
                shiftedByte >>= 1
            }
            bitsArray += bits.reversed()
        }
        
        return bitsArray
    }
    
    var booleans: Array<Bool> {
        self.bits.map{ ($0 == .one) ? true : false }
    }
}

extension Data {
    var reversed: Data {
        Data(self.reversed())
    }
}

extension Data {
    var hexadecimal: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    var uint32: UInt32 {
        return self.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self)
        }
    }
}

extension Data {
    static func generateSecuredRandomBytes(count: Int) -> Data {
        var bytes: Array<UInt8> = .init(repeating: 0, count: count)
        let status: Int32 = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { fatalError("Failed to generate random bytes") }
        
        return .init(bytes)
    }
}

extension Data {
    func convertTo5Bit(pad: Bool) -> Data {
        var jar: Int = 0
        var bits: UInt8 = 0
        let maximumValue: Int = 0b000_11111
        var converted: [UInt8] = [UInt8]()
        for byte in self {
            jar = (jar << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                converted.append(UInt8(jar >> Int(bits) & maximumValue))
            }
        }
        
        let lastBits: UInt8 = UInt8(jar << (5 - bits) & maximumValue)
        if pad && bits > 0 {
            converted.append(lastBits)
        }
        return Data(converted)
    }
}

protocol DataConvertible {
    init?(data: Data)
    var data: Data { get }
}

extension DataConvertible where Self: ExpressibleByIntegerLiteral{
    init?(data: Data) {
        var value: Self = 0
        guard data.count == MemoryLayout.size(ofValue: value) else { return nil }
        _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
        self = value
    }

    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt8: DataConvertible {}
extension UInt16: DataConvertible {}
extension UInt32: DataConvertible {}
extension UInt64: DataConvertible {}
