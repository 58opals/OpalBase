import Foundation
import Testing
@testable import OpalBase

@Suite("Account Payment", .tags(.wallet, .integration))
struct AccountPaymentTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let mnemonicWords = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]
    private static let sampleRecipientAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("Payment stores initialization values")
    func testPaymentInitializationStoresConfiguration() throws {
        let recipientAddress = try Address(Self.sampleRecipientAddress)
        let amount = try Satoshi(1_500)
        let payment = Account.Payment(recipients: [
            .init(address: recipientAddress, amount: amount)
        ],
                                      feePerByte: 12,
                                      coinSelection: .branchAndBound,
                                      allowDustDonation: true)
        
        #expect(payment.recipients.count == 1)
        if let storedRecipient = payment.recipients.first {
            #expect(storedRecipient.address.string == recipientAddress.string)
            #expect(storedRecipient.amount.uint64 == amount.uint64)
        }
        #expect(payment.feePerByte == 12)
        switch payment.coinSelection {
        case .branchAndBound:
            #expect(true)
        default:
            #expect(Bool(false), "Expected branch and bound coin selection")
        }
        #expect(payment.allowDustDonation)
    }
    
    @Test("sendPayment rejects missing recipients", .timeLimit(.minutes(1)))
    func testSendPaymentRejectsEmptyRecipients() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        await account.purgeOutbox()
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        
        let payment = Account.Payment(recipients: .init())
        
        await #expect(throws: Account.Error.paymentHasNoRecipients) {
            _ = try await account.sendPayment(payment, using: session)
        }
    }
    
    @Test("sendPayment rejects amounts that exceed the supply cap", .timeLimit(.minutes(1)))
    func testSendPaymentFailsWhenExceedingMaximumAmount() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        await account.purgeOutbox()
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        
        let recipientAddress = try Address(Self.sampleRecipientAddress)
        let maximum = try Satoshi(Satoshi.maximumSatoshi)
        let overflow = try Satoshi(1)
        
        let payment = Account.Payment(recipients: [
            .init(address: recipientAddress, amount: maximum),
            .init(address: recipientAddress, amount: overflow)
        ])
        
        await #expect(throws: Account.Error.paymentExceedsMaximumAmount) {
            _ = try await account.sendPayment(payment, using: session)
        }
    }
    
    @Test("sendPayment fails when the wallet lacks spendable UTXOs", .timeLimit(.minutes(1)))
    func testSendPaymentFailsWhenInsufficientFunds() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        await account.purgeOutbox()
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        
        let recipientAddress = try Address(Self.sampleRecipientAddress)
        let amount = try Satoshi(1_000)
        let payment = Account.Payment(recipients: [
            .init(address: recipientAddress, amount: amount)
        ])
        
        do {
            _ = try await account.sendPayment(payment, using: session)
            #expect(Bool(false), "Expected insufficient funds error")
        } catch let error as Account.Error {
            switch error {
            case .coinSelectionFailed(let underlyingError):
                if let addressBookError = underlyingError as? Address.Book.Error {
                    switch addressBookError {
                    case .insufficientFunds:
                        #expect(true)
                    default:
                        #expect(Bool(false), "Expected insufficient funds from address book")
                    }
                } else {
                    #expect(Bool(false), "Expected Address.Book.Error")
                }
            default:
                #expect(Bool(false), "Expected coinSelectionFailed error, received \(error)")
            }
        } catch {
            #expect(Bool(false), "Expected Account.Error, received \(error)")
        }
    }
    
    @Test("resubmitPendingTransactions keeps failed broadcasts queued", .timeLimit(.minutes(1)))
    func testResubmitPendingTransactionsKeepsFailedBroadcastsQueued() async throws {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        await account.purgeOutbox()
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        try await session.start()
        
        let receivingEntry = try await account.addressBook.selectNextEntry(for: .receiving, fetchBalance: false)
        let previousHash = Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let utxoValue: UInt64 = 200_000
        let unspentOutput = Transaction.Output.Unspent(value: utxoValue,
                                                       lockingScript: receivingEntry.address.lockingScript.data,
                                                       previousTransactionHash: previousHash,
                                                       previousTransactionOutputIndex: 0)
        await account.addressBook.addUTXO(unspentOutput)
        
        let recipientAddress = try Address(Self.sampleRecipientAddress)
        let amount = try Satoshi(50_000)
        let payment = Account.Payment(recipients: [
            .init(address: recipientAddress, amount: amount)
        ])
        
        do {
            _ = try await account.sendPayment(payment, using: session)
            #expect(Bool(false), "Expected broadcast failure")
        } catch let error as Account.Error {
            switch error {
            case .broadcastFailed:
                #expect(true)
            default:
                #expect(Bool(false), "Expected broadcast failure, received \(error)")
            }
        }
        
        let pendingAfterFailure = await account.outbox.loadPendingTransactions()
        #expect(pendingAfterFailure.count == 1)
        
        await account.resubmitPendingTransactions(using: session)
        await account.processQueuedRequests()
        try await Task.sleep(for: .seconds(30))
        
        let pendingAfterResubmit = await account.outbox.loadPendingTransactions()
        #expect(pendingAfterResubmit.count == 1)
        
        await account.purgeOutbox()
    }
}
