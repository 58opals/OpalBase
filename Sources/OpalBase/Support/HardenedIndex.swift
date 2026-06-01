// HardenedIndex.swift

enum HardenedIndex {
    static let bit: UInt32 = 0x8000_0000
    static let maxUnhardenedValue: UInt32 = bit &- 1
    static func isHardened(_ value: UInt32) -> Bool { (value & bit) != 0 }
    static func harden(_ value: UInt32) -> UInt32 { value | bit }
    static func unharden(_ value: UInt32) -> UInt32 { value & ~bit }
}
