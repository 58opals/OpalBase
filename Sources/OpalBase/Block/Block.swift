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
    
    func encode() -> Data {
        var writer = Data.Writer()
        writer.writeData(header.encode())
        writer.writeCompactSize(CompactSize(value: UInt64(transactions.count)))
        transactions.forEach { writer.writeData($0.encode()) }
        return writer.data
    }
    
    
    /*
     static func decode(from data: Data) throws -> (block: Block, bytesRead: Int) {
         var reader = Data.Reader(data)
         let header = try Header.decode(from: &reader)
         let transactionCount = try reader.readCompactSize()
         let transactions = try (0..<transactionCount.value).map { _ -> Transaction in
             return try Transaction.decode(from: reader.data).transaction
         }
         let block = Block(header: header, transactions: transactions)
         return (block, reader.bytesRead)
     }
     */

    static func decode(from data: Data) throws -> (block: Block, bytesRead: Int) {
        var index = data.startIndex
        let (header, headerBytesRead) = try Header.decode(from: data)
        index += headerBytesRead
        let (transactionCount, countBytesRead) = try CompactSize.decode(from: data[index...])
        index += countBytesRead
        let transactions = try (0..<transactionCount.value).map { _ -> Transaction in
            let (transaction, transactionBytesRead) = try Transaction.decode(from: data[index...])
            index += transactionBytesRead
            return transaction
        }
        let block = Block(header: header, transactions: transactions)
        return (block, index - data.startIndex)
    }
}
