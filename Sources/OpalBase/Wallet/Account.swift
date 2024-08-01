import Foundation

struct Account {
    let extendedKey: PrivateKey.Extended
    let accountIndex: UInt32
    var addressBook: Address.Book
    
    init(extendedKey: PrivateKey.Extended, accountIndex: UInt32) async throws {
        self.extendedKey = extendedKey
        self.accountIndex = accountIndex
        self.addressBook = try Address.Book(extendedKey: extendedKey)
    }
}

extension Account {
    func createTransaction(from: CashAddress, to: CashAddress, value: Satoshi) async throws -> Transaction {
        // Fetch UTXOs for the sender address
        let utxos = try await fetchUTXOs(for: from)
        
        // Calculate the total amount available and select UTXOs for the transaction
        var totalInput: Satoshi = try Satoshi(0)
        var selectedUTXOs: [Transaction.Output.Unspent] = []
        for utxo in utxos {
            totalInput = try totalInput + Satoshi(utxo.amount)
            selectedUTXOs.append(utxo)
            if totalInput >= value {
                break
            }
        }
        
        // Ensure sufficient funds are available
        guard totalInput >= value else {
            throw Transaction.Error.insufficientFunds
        }
        
        // Create inputs for the transaction
        let inputs: [Transaction.Input] = selectedUTXOs.map { utxo in
            return Transaction.Input(
                previousTransactionHash: utxo.transactionHash,
                previousTransactionIndex: utxo.outputIndex,
                unlockingScript: Data(), // Placeholder, will be replaced with actual signature later
                sequence: UInt32.max
            )
        }
        
        // Create output for the recipient
        let recipientOutput = Transaction.Output(
            value: value.value,
            lockingScript: to.script.data
        )
        
        // Calculate the change amount and create change output if needed
        let changeValue = try totalInput - value
        var outputs: [Transaction.Output] = [recipientOutput]
        
        if changeValue > (try Satoshi(0)) {
            let changeOutput = Transaction.Output(
                value: changeValue.value,
                lockingScript: from.script.data
            )
            outputs.append(changeOutput)
        }
        
        // Create the transaction
        let transaction = Transaction(
            version: 2,
            inputs: inputs,
            outputs: outputs,
            lockTime: 0
        )
        
        // Sign each input
        var signedTransaction = transaction
        for (index, utxo) in selectedUTXOs.enumerated() {
            let privateKey = try addressBook.getPrivateKey(for: from)
            let outputBeingSpent = Transaction.Output(
                value: utxo.amount,
                lockingScript: utxo.lockingScript
            )
            let hashType: Transaction.HashType = .all(anyoneCanPay: false)
            let signature = try signedTransaction.signInput(
                privateKey: privateKey.rawData,
                index: index,
                hashType: hashType,
                outputBeingSpent: outputBeingSpent,
                format: .der
            )
            signedTransaction = signedTransaction.addSignature(signature, index: index)
        }
        
        return signedTransaction
    }
}
