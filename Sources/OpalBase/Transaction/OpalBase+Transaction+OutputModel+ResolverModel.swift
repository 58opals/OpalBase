// OpalBase+Transaction+OutputModel+ResolverModel.swift

import Foundation

extension _OpalBase.Transaction.OutputModel {
    struct ResolverModel {
        private var buckets: [OpalBase.Transaction.OutputModel.FingerprintModel: [OpalBase.Transaction.OutputModel]]
        
        init(outputs: [OpalBase.Transaction.OutputModel]) {
            var buckets: [OpalBase.Transaction.OutputModel.FingerprintModel: [OpalBase.Transaction.OutputModel]] = .init()
            buckets.reserveCapacity(outputs.count)
            for output in outputs.reversed() {
                buckets[output.fingerprint, default: .init()].append(output)
            }
            self.buckets = buckets
        }
        
        mutating func popFirst(matching candidate: OpalBase.Transaction.OutputModel) -> OpalBase.Transaction.OutputModel? {
            let key = candidate.fingerprint
            guard var bucket = buckets[key], !bucket.isEmpty else { return nil }
            
            let resolved = bucket.removeLast()
            if bucket.isEmpty {
                buckets[key] = nil
            } else {
                buckets[key] = bucket
            }
            return resolved
        }
        
        mutating func resolve(_ candidates: [OpalBase.Transaction.OutputModel]) -> [OpalBase.Transaction.OutputModel] {
            candidates.compactMap { popFirst(matching: $0) }
        }
    }
}

extension _OpalBase.Transaction.OutputModel.ResolverModel {
    static func resolve(_ candidates: [OpalBase.Transaction.OutputModel], in outputs: [OpalBase.Transaction.OutputModel]) -> [OpalBase.Transaction.OutputModel] {
        var resolver = Self(outputs: outputs)
        return resolver.resolve(candidates)
    }
}

extension _OpalBase.Transaction.OutputModel {
    struct FingerprintModel: Hashable {
        let lockingScript: Data
        let value: UInt64
        let tokenData: OpalBase.CashTokens.TokenData?
    }
}

extension _OpalBase.Transaction.OutputModel {
    var fingerprint: OpalBase.Transaction.OutputModel.FingerprintModel {
        .init(lockingScript: lockingScript, value: value, tokenData: tokenData)
    }
}
