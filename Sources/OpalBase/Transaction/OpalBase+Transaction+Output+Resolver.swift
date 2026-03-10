// OpalBase+Transaction+Output+Resolver.swift

import Foundation

extension _OpalBase.Transaction.Output {
    struct Resolver {
        private var buckets: [OpalBase.Transaction.Output.Fingerprint: [OpalBase.Transaction.Output]]
        
        init(outputs: [OpalBase.Transaction.Output]) {
            var buckets: [OpalBase.Transaction.Output.Fingerprint: [OpalBase.Transaction.Output]] = .init()
            buckets.reserveCapacity(outputs.count)
            for output in outputs.reversed() {
                buckets[output.fingerprint, default: .init()].append(output)
            }
            self.buckets = buckets
        }
        
        mutating func popFirst(matching candidate: OpalBase.Transaction.Output) -> OpalBase.Transaction.Output? {
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
        
        mutating func resolve(_ candidates: [OpalBase.Transaction.Output]) -> [OpalBase.Transaction.Output] {
            candidates.compactMap { popFirst(matching: $0) }
        }
    }
}

extension _OpalBase.Transaction.Output.Resolver {
    static func resolve(_ candidates: [OpalBase.Transaction.Output], in outputs: [OpalBase.Transaction.Output]) -> [OpalBase.Transaction.Output] {
        var resolver = Self(outputs: outputs)
        return resolver.resolve(candidates)
    }
}
