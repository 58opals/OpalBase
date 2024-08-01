import Foundation

struct Transaction {
    let version: UInt32
    let inputs: [Input]
    let outputs: [Output]
    let lockTime: UInt32
    
    /// Initializes a Transaction instance.
    /// - Parameters:
    ///   - version: The transaction version.
    ///   - inputs: The list of inputs.
    ///   - outputs: The list of outputs.
    ///   - lockTime: The lock time.
    init(version: UInt32, inputs: [Input], outputs: [Output], lockTime: UInt32) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.lockTime = lockTime
    }
    
    /// Encodes the Transaction into Data.
    /// - Returns: The encoded data.
    func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: withUnsafeBytes(of: version.littleEndian, Array.init))
        
        data.append(CompactSize(value: UInt64(inputs.count)).encode())
        inputs.forEach { data.append($0.encode()) }
        
        data.append(CompactSize(value: UInt64(outputs.count)).encode())
        outputs.forEach { data.append($0.encode()) }
        
        data.append(contentsOf: withUnsafeBytes(of: lockTime.littleEndian, Array.init))
        
        return data
    }
    
    /// Decodes a Transaction instance from Data.
    /// - Parameter data: The data to decode from.
    /// - Throws: `CompactSize.Error` if decoding fails.
    /// - Returns: A tuple containing the decoded Transaction and the number of bytes read.
    static func decode(from data: Data) throws -> (transaction: Transaction, bytesRead: Int) {
        var index = data.startIndex
        
        let (version, newIndex1): (UInt32, Data.Index) = data.extractValue(from: index)
        index = newIndex1
        
        let (inputsCount, inputsCountSize) = try CompactSize.decode(from: data[index...])
        index += inputsCountSize
        
        let inputs = try (0..<inputsCount.value).map { _ -> Input in
            let (input, inputSize) = try Input.decode(from: data[index...])
            index += inputSize
            return input
        }
        
        let (outputsCount, outputsCountSize) = try CompactSize.decode(from: data[index...])
        index += outputsCountSize
        
        let outputs = try (0..<outputsCount.value).map { _ -> Output in
            let (output, outputSize) = try Output.decode(from: data[index...])
            index += outputSize
            return output
        }
        
        let (lockTime, newIndex2): (UInt32, Data.Index) = data.extractValue(from: index)
        index = newIndex2
        
        let transaction = Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        
        return (transaction, index)
    }
}
