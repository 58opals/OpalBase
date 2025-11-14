// Transaction+HashType.swift

import Foundation

extension Transaction {
    public struct HashType {
        public enum Mode {
            case all
            case none
            case single
        }
        
        private enum Modifier: UInt32 {
            case forkId = 0x40
            case anyoneCanPay = 0x80
        }
        
        private struct Options {
            let modifierBitMask: UInt32
            
            init(isAnyoneCanPayEnabled: Bool) {
                var bitMask = Modifier.forkId.rawValue
                if isAnyoneCanPayEnabled {
                    bitMask |= Modifier.anyoneCanPay.rawValue
                }
                self.modifierBitMask = bitMask
            }
            
            var isAnyoneCanPayEnabled: Bool {
                (modifierBitMask & Modifier.anyoneCanPay.rawValue) == Modifier.anyoneCanPay.rawValue
            }
        }
        
        public let mode: Mode
        private let options: Options
        
        private init(mode: Mode, options: Options) {
            self.mode = mode
            self.options = options
        }
        
        public init(mode: Mode, isAnyoneCanPayEnabled: Bool = false) {
            self.init(mode: mode, options: Options(isAnyoneCanPayEnabled: isAnyoneCanPayEnabled))
        }
        
        public static func all(anyoneCanPay: Bool = false) -> HashType {
            HashType(mode: .all, isAnyoneCanPayEnabled: anyoneCanPay)
        }
        
        public static func none(anyoneCanPay: Bool = false) -> HashType {
            HashType(mode: .none, isAnyoneCanPayEnabled: anyoneCanPay)
        }
        
        public static func single(anyoneCanPay: Bool = false) -> HashType {
            HashType(mode: .single, isAnyoneCanPayEnabled: anyoneCanPay)
        }
        
        var value: UInt32 {
            let base: UInt32
            switch mode {
            case .all:
                base = 0x01
            case .none:
                base = 0x02
            case .single:
                base = 0x03
            }
            
            return base | options.modifierBitMask
        }
        
        var isAnyoneCanPay: Bool {
            options.isAnyoneCanPayEnabled
        }
        
        var isAllWithoutAnyoneCanPay: Bool {
            mode == .all && !options.isAnyoneCanPayEnabled
        }
    }
}
