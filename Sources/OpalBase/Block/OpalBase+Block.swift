// OpalBase+Block.swift

import Foundation

extension OpalBase {
    public struct Block {
        public let header: Header
        public let transactions: [OpalBase.Transaction]
        
        public init(header: Header,
                    transactions: [OpalBase.Transaction]) {
            self.header = header
            self.transactions = transactions
        }
        
        func encode() throws -> Data {
            guard !transactions.isEmpty else { throw Error.emptyTransactionList }
            let expectedHeaderHashLength = 32
            guard header.previousBlockHash.count == expectedHeaderHashLength else {
                throw Error.invalidPreviousBlockHashLength(
                    expected: expectedHeaderHashLength,
                    actual: header.previousBlockHash.count
                )
            }
            guard header.merkleRoot.count == expectedHeaderHashLength else {
                throw Error.invalidMerkleRootLength(
                    expected: expectedHeaderHashLength,
                    actual: header.merkleRoot.count
                )
            }
            try Self.validateMerkleRoot(header.merkleRoot, transactions: transactions)
            var writer = Data.Writer()
            writer.writeData(header.encode())
            writer.writeCompactSize(CompactSize(value: UInt64(transactions.count)))
            for transaction in transactions {
                writer.writeData(try transaction.encode())
            }
            return writer.data
        }
        
        static func decode(from data: Data) throws -> (block: OpalBase.Block, bytesRead: Int) {
            var reader = Data.Reader(data)
            let header = try Header.decode(from: &reader)
            let transactionCount = try reader.readCompactSize()
            guard transactionCount.value <= UInt64(Int.max) else { throw Error.transactionCountOverflow(transactionCount.value) }
            guard transactionCount.value > 0 else { throw Error.emptyTransactionList }
            try validateDeclaredTransactionCount(
                transactionCount.value,
                remainingByteCount: reader.remainingData.count
            )
            let transactions = try (0..<Int(transactionCount.value)).map { _ -> OpalBase.Transaction in
                try OpalBase.Transaction.decode(from: &reader)
            }
            let block = OpalBase.Block(header: header, transactions: transactions)
            try validateMerkleRoot(header.merkleRoot, transactions: transactions)
            return (block, reader.bytesRead)
        }

        static func computeMerkleRoot(for transactions: [OpalBase.Transaction]) throws -> Data {
            guard !transactions.isEmpty else { throw Error.emptyTransactionList }
            var level = try transactions.map { transaction in
                OpalCryptoAdapter.hash256(try transaction.encode())
            }

            while level.count > 1 {
                var nextLevel: [Data] = .init()
                nextLevel.reserveCapacity((level.count + 1) / 2)
                for index in stride(from: 0, to: level.count, by: 2) {
                    let left = level[index]
                    let right = index + 1 < level.count ? level[index + 1] : left
                    nextLevel.append(OpalCryptoAdapter.hash256(left + right))
                }
                level = nextLevel
            }

            return level[0]
        }

        private static func validateMerkleRoot(
            _ merkleRoot: Data,
            transactions: [OpalBase.Transaction]
        ) throws {
            let computedMerkleRoot = try computeMerkleRoot(for: transactions)
            guard merkleRoot == computedMerkleRoot else {
                throw Error.merkleRootMismatch(computed: computedMerkleRoot, header: merkleRoot)
            }
        }

        private static let minimumEncodedTransactionByteCount = 60

        private static func validateDeclaredTransactionCount(
            _ count: UInt64,
            remainingByteCount: Int
        ) throws {
            guard count <= UInt64(remainingByteCount / minimumEncodedTransactionByteCount) else {
                throw Data.Error.indexOutOfRange
            }
        }
    }
}
