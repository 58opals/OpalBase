// Opal Base by 58 Opals

import Foundation

struct VLInt: ExpressibleByIntegerLiteral {
    typealias IntegerLiteralType = UInt64
    
    let underlyingValue: UInt64
    let data: Data
    
    init(_ value: UInt64) {
        let firstRange = UInt64(0x0)...UInt64(0xfc)
        let secondRange = UInt64(0xfd)...UInt64(0xffff)
        let thirdRange = UInt64(0x10000)...UInt64(0xffffffff)
        let fourthRange = UInt64(0x100000000)...UInt64(0xffffffffffffffff)
        
        self.underlyingValue = value
        
        switch value {
        case firstRange:
            self.data = value.data.prefix(1)
        case secondRange:
            self.data = Data([0xfd]) + value.data.prefix(2)
        case thirdRange:
            self.data = Data([0xfe]) + value.data.prefix(4)
        case fourthRange:
            self.data = Data([0xff]) + value.data.prefix(8)
        default:
            fatalError()
        }
    }
    
    init(_ value: Int) {
        self.init(UInt64(value))
    }
    
    init(integerLiteral value: UInt64) {
        self.init(value)
    }
}

extension VLInt: CustomStringConvertible {
    var description: String { underlyingValue.description }
}
