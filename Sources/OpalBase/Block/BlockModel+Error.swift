// BlockModel.swift

import Foundation

public struct BlockModel {
    public let header: HeaderModel
    public let transactions: [TransactionModel]
    
    public init(header: HeaderModel,
                transactions: [TransactionModel]) {
        self.header = header
        self.transactions = transactions
    }
    
    func encode() throws -> Data {
        var writer = Data.WriterModel()
        writer.writeData(header.encode())
        writer.writeCompactSize(CompactSizeModel(value: UInt64(transactions.count)))
        for transaction in transactions {
            writer.writeData(try transaction.encode())
        }
        return writer.data
    }
    
    static func decode(from data: Data) throws -> (block: BlockModel, bytesRead: Int) {
        var reader = Data.ReaderModel(data)
        let header = try HeaderModel.decode(from: &reader)
        let transactionCount = try reader.readCompactSize()
        guard transactionCount.value <= UInt64(Int.max) else { throw Error.transactionCountOverflow(transactionCount.value) }
        let transactions = try (0..<Int(transactionCount.value)).map { _ -> TransactionModel in
            try TransactionModel.decode(from: &reader)
        }
        let block = BlockModel(header: header, transactions: transactions)
        return (block, reader.bytesRead)
    }
}

extension BlockModel {
    enum Error: Swift.Error {
        case transactionCountOverflow(UInt64)
    }
}
