// Block.swift

import Foundation

struct Block {
    let header: Header
    let transactions: [Transaction]
    
    func encode() -> Data {
        var data = header.encode()
        data.append(CompactSize(value: UInt64(transactions.count)).encode())
        transactions.forEach { data.append($0.encode()) }
        return data
    }
    
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
        return (block, index)
    }
}
