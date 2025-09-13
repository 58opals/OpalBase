// Transaction+HashType.swift

import Foundation

extension Transaction {
    enum HashType {
        case all(anyoneCanPay: Bool)
        case none(anyoneCanPay: Bool)
        case single(anyoneCanPay: Bool)
        
        enum Modifier: UInt32 {
            case forkId = 0x40
            case anyoneCanPay = 0x80
        }
        
        var value: UInt32 {
            var value: UInt32 = 0
            switch self {
            case .all(let anyoneCanPay):
                value = 0x01 | Modifier.forkId.rawValue | (anyoneCanPay ? Modifier.anyoneCanPay.rawValue : 0)
            case .none(let anyoneCanPay):
                value = 0x02 | Modifier.forkId.rawValue | (anyoneCanPay ? Modifier.anyoneCanPay.rawValue : 0)
            case .single(let anyoneCanPay):
                value = 0x03 | Modifier.forkId.rawValue | (anyoneCanPay ? Modifier.anyoneCanPay.rawValue : 0)
            }
            return value
        }
        
        var isAnyoneCanPay: Bool {
            switch self {
            case .all(let anyoneCanPay):
                if anyoneCanPay { return true }
                else { return false }
            case .none(let anyoneCanPay):
                if anyoneCanPay { return true }
                else { return false }
            case .single(let anyoneCanPay):
                if anyoneCanPay { return true }
                else { return false }
            }
        }
        
        var isNotAnyoneCanPayWithAllHashType: Bool {
            switch self {
            case .all(let anyoneCanPay):
                if anyoneCanPay { return false }
                else { return true }
            case .none(_):
                return false
            case .single(_):
                return false
            }
        }
    }
}
