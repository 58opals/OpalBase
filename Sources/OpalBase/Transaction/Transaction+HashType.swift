// Transaction+HashType.swift

import Foundation

extension Transaction {
    public struct HashType: Sendable {
        public enum Mode: Sendable {
            case all
            case none
            case single
        }
        
        private enum Modifier: UInt32 {
            case unspentTransactionOutputs = 0x20
            case forkId = 0x40
            case anyoneCanPay = 0x80
        }
        
        private struct Options {
            let modifierBitMask: UInt32
            
            init(isAnyoneCanPayEnabled: Bool, isUnspentTransactionOutputsEnabled: Bool) {
                var bitMask = Modifier.forkId.rawValue
                if isAnyoneCanPayEnabled {
                    bitMask |= Modifier.anyoneCanPay.rawValue
                }
                if isUnspentTransactionOutputsEnabled {
                    bitMask |= Modifier.unspentTransactionOutputs.rawValue
                }
                self.modifierBitMask = bitMask
            }
            
            var isAnyoneCanPayEnabled: Bool {
                (modifierBitMask & Modifier.anyoneCanPay.rawValue) == Modifier.anyoneCanPay.rawValue
            }
            
            var isForkIdEnabled: Bool {
                (modifierBitMask & Modifier.forkId.rawValue) == Modifier.forkId.rawValue
            }
            
            var isUnspentTransactionOutputsEnabled: Bool {
                (modifierBitMask & Modifier.unspentTransactionOutputs.rawValue)
                == Modifier.unspentTransactionOutputs.rawValue
            }
        }
        
        public let mode: Mode
        private let options: Options
        
        private init(mode: Mode, options: Options) {
            self.mode = mode
            self.options = options
        }
        
        public init(mode: Mode,
                    isAnyoneCanPayEnabled: Bool = false,
                    isUnspentTransactionOutputsEnabled: Bool = false) {
            self.init(mode: mode,
                      options: Options(isAnyoneCanPayEnabled: isAnyoneCanPayEnabled,
                                       isUnspentTransactionOutputsEnabled: isUnspentTransactionOutputsEnabled))
        }
        
        public static func makeAll(anyoneCanPay: Bool = false,
                                   includesUnspentTransactionOutputs: Bool = false) -> HashType {
            HashType(mode: .all,
                     isAnyoneCanPayEnabled: anyoneCanPay,
                     isUnspentTransactionOutputsEnabled: includesUnspentTransactionOutputs)
        }
        
        public static func makeNone(anyoneCanPay: Bool = false,
                                    includesUnspentTransactionOutputs: Bool = false) -> HashType {
            HashType(mode: .none,
                     isAnyoneCanPayEnabled: anyoneCanPay,
                     isUnspentTransactionOutputsEnabled: includesUnspentTransactionOutputs)
        }
        
        public static func makeSingle(anyoneCanPay: Bool = false,
                                      includesUnspentTransactionOutputs: Bool = false) -> HashType {
            HashType(mode: .single,
                     isAnyoneCanPayEnabled: anyoneCanPay,
                     isUnspentTransactionOutputsEnabled: includesUnspentTransactionOutputs)
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
        
        var isUnspentTransactionOutputsEnabled: Bool {
            options.isUnspentTransactionOutputsEnabled
        }
        
        var isAllWithoutAnyoneCanPay: Bool {
            mode == .all && !options.isAnyoneCanPayEnabled
        }
    }
}

extension Transaction.HashType {
    func validate() throws {
        guard !(isAnyoneCanPay && isUnspentTransactionOutputsEnabled) else {
            throw Transaction.Error.unsupportedHashType
        }
        
        guard !isUnspentTransactionOutputsEnabled || options.isForkIdEnabled else {
            throw Transaction.Error.unsupportedHashType
        }
    }
}
