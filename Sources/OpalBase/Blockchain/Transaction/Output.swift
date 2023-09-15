// Opal Base by 58 Opals

import Foundation

extension Transaction {
    struct Output: Hashable {
        let value: UInt64
        let lockingScript: Data
        
        var scriptSize: VLInt { .init(lockingScript.count) }
    }
}

extension Transaction.Output {
    
}

extension Transaction.Output: Serializable {
    func serialize() -> Data {
        let raw: Data =
            value.data +
            scriptSize.data +
            lockingScript
        
        return raw
    }
}
