// Transaction+Output+Resolver.swift

import Foundation

extension Transaction.Output {
    struct Resolver {
        private var buckets: [Transaction.Output.Fingerprint: [Transaction.Output]]
        
        init(outputs: [Transaction.Output]) {
            var buckets: [Transaction.Output.Fingerprint: [Transaction.Output]] = .init()
            buckets.reserveCapacity(outputs.count)
            for output in outputs.reversed() {
                buckets[output.fingerprint, default: .init()].append(output)
            }
            self.buckets = buckets
        }
        
        mutating func popFirst(matching candidate: Transaction.Output) -> Transaction.Output? {
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
        
        mutating func resolve(_ candidates: [Transaction.Output]) -> [Transaction.Output] {
            candidates.compactMap { popFirst(matching: $0) }
        }
    }
}

extension Transaction.Output.Resolver {
    static func resolve(_ candidates: [Transaction.Output], in outputs: [Transaction.Output]) -> [Transaction.Output] {
        var resolver = Self(outputs: outputs)
        return resolver.resolve(candidates)
    }
}

extension Transaction.Output {
    struct Fingerprint: Hashable {
        let lockingScript: Data
        let value: UInt64
        let tokenData: CashTokens.TokenData?
    }
}

extension Transaction.Output {
    var fingerprint: Transaction.Output.Fingerprint {
        .init(lockingScript: lockingScript, value: value, tokenData: tokenData)
    }
}
