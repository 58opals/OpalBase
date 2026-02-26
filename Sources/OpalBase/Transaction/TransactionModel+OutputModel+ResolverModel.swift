// TransactionModel+OutputModel+ResolverModel.swift

import Foundation

extension TransactionModel.OutputModel {
    struct ResolverModel {
        private var buckets: [TransactionModel.OutputModel.FingerprintModel: [TransactionModel.OutputModel]]
        
        init(outputs: [TransactionModel.OutputModel]) {
            var buckets: [TransactionModel.OutputModel.FingerprintModel: [TransactionModel.OutputModel]] = .init()
            buckets.reserveCapacity(outputs.count)
            for output in outputs.reversed() {
                buckets[output.fingerprint, default: .init()].append(output)
            }
            self.buckets = buckets
        }
        
        mutating func popFirst(matching candidate: TransactionModel.OutputModel) -> TransactionModel.OutputModel? {
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
        
        mutating func resolve(_ candidates: [TransactionModel.OutputModel]) -> [TransactionModel.OutputModel] {
            candidates.compactMap { popFirst(matching: $0) }
        }
    }
}

extension TransactionModel.OutputModel.ResolverModel {
    static func resolve(_ candidates: [TransactionModel.OutputModel], in outputs: [TransactionModel.OutputModel]) -> [TransactionModel.OutputModel] {
        var resolver = Self(outputs: outputs)
        return resolver.resolve(candidates)
    }
}

extension TransactionModel.OutputModel {
    struct FingerprintModel: Hashable {
        let lockingScript: Data
        let value: UInt64
        let tokenData: CashTokensModel.TokenData?
    }
}

extension TransactionModel.OutputModel {
    var fingerprint: TransactionModel.OutputModel.FingerprintModel {
        .init(lockingScript: lockingScript, value: value, tokenData: tokenData)
    }
}
