// Block.swift

import Foundation

public struct Block {
    public let header: Header
    public let transactions: [Transaction]
    
    public init(header: Header,
                transactions: [Transaction]) {
        self.header = header
        self.transactions = transactions
    }
    
    func encode() throws -> Data {
        var writer = Data.Writer()
        writer.writeData(header.encode())
        writer.writeCompactSize(CompactSize(value: UInt64(transactions.count)))
        for transaction in transactions {
            writer.writeData(try transaction.encode())
        }
        return writer.data
    }
    
    static func decode(from data: Data) throws -> (block: Block, bytesRead: Int) {
        var reader = Data.Reader(data)
        let header = try Header.decode(from: &reader)
        let transactionCount = try reader.readCompactSize()
        guard transactionCount.value <= UInt64(Int.max) else { throw Error.transactionCountOverflow(transactionCount.value) }
        let transactions = try (0..<Int(transactionCount.value)).map { _ -> Transaction in
            try Transaction.decode(from: &reader)
        }
        let block = Block(header: header, transactions: transactions)
        return (block, reader.bytesRead)
    }
}

extension Block {
    enum Error: Swift.Error {
        case transactionCountOverflow(UInt64)
    }
}
