// UnicodeScalar+HexadecimalNibble.swift

import Foundation

extension Unicode.Scalar {
    var hexadecimalNibble: UInt8? {
        switch value {
        case 48...57:
            return UInt8(value - 48)
        case 65...70:
            return UInt8(value - 55)
        case 97...102:
            return UInt8(value - 87)
        default:
            return nil
        }
    }
}
