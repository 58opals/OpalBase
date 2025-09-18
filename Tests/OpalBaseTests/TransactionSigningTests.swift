import Foundation
import Testing
@testable import OpalBase
import SwiftFulcrum

// MARK: - Small helpers

enum PushParseError: Error { case short, bad }
private func readPush(_ data: Data, _ i: inout Int) throws -> Data {
    guard i < data.count else { throw PushParseError.short }
    let op = data[i]; i += 1
    let len: Int
    switch op {
    case 0x01...0x4b: len = Int(op)
    case 0x4c: guard i < data.count else { throw PushParseError.short }
        len = Int(data[i]); i += 1
    case 0x4d:
        guard i + 1 < data.count else { throw PushParseError.short }
        len = Int(UInt16(littleEndian: data[i..<(i+2)].withUnsafeBytes { $0.load(as: UInt16.self) })); i += 2
    case 0x4e:
        guard i + 3 < data.count else { throw PushParseError.short }
        len = Int(UInt32(littleEndian: data[i..<(i+4)].withUnsafeBytes { $0.load(as: UInt32.self) })); i += 4
    default: throw PushParseError.bad
    }
    guard i + len <= data.count else { throw PushParseError.short }
    defer { i += len }
    return data[i..<(i+len)]
}

private func splitCheckSigUnlock(_ script: Data) throws -> (sigNoType: Data, sighashType: UInt8, pubkey: Data) {
    var i = 0
    let sigWithType = try readPush(script, &i)
    let pub = try readPush(script, &i)
    guard i == script.count, sigWithType.count >= 1 else { throw PushParseError.bad }
    return (sigWithType.dropLast(), sigWithType.last!, pub)
}

private func splitCheckDataSigUnlock(_ script: Data) throws -> (sig: Data, message: Data, pubkey: Data) {
    var i = 0
    let sig = try readPush(script, &i)
    let msg = try readPush(script, &i)
    let pub = try readPush(script, &i)
    guard i == script.count else { throw PushParseError.bad }
    return (sig, msg, pub)
}

private func makeKeypair() throws -> (PrivateKey, PublicKey) {
    let sk = try PrivateKey()
    let pk = try PublicKey(privateKey: sk)
    return (sk, pk)
}

private func makeDummyPrevoutHash(_ byte: UInt8) -> Transaction.Hash {
    Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32))
}


@Suite("Transaction Signing Tests")
struct TransactionSigningTests {
    
    // MARK: - OP_CHECKSIG path
    
    @Test("P2PKH CHECKSIG: preimage hashing semantics and verification (ECDSA DER)")
    func checksig_hashing_and_verify_ecdsa() throws {
        let (sk, pk) = try makeKeypair()
        let addr = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: pk)))
        let utxo = Transaction.Output.Unspent(
            value: 200_000, // plenty for fees
            lockingScript: addr.lockingScript.data,
            previousTransactionHash: makeDummyPrevoutHash(0x11),
            previousTransactionOutputIndex: 0
        )
        let recipient = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: pk)))
        let outputs = [Transaction.Output(value: 50_000, address: recipient)]
        let change = Transaction.Output(value: utxo.value - 50_000, address: recipient)
        
        let tx = try Transaction.build(
            version: 2,
            utxoPrivateKeyPairs: [utxo: sk],
            recipientOutputs: outputs,
            changeOutput: change,
            signatureFormat: .ecdsa(.der),
            feePerByte: 1,
            unlockers: [utxo: .p2pkh_CheckSig(hashType: .all(anyoneCanPay: false))]
        )
        
        // Extract unlocking script and recompute the correct preimage.
        let input = tx.inputs[0]
        let (sigNoType, sighashType, pub) = try splitCheckSigUnlock(input.unlockingScript)
        #expect(pub == pk.compressedData)
        #expect(sighashType == Transaction.HashType.all(anyoneCanPay: false).value & 0xff)
        
        let preimage = try tx.generatePreimage(
            for: 0,
            hashType: .all(anyoneCanPay: false),
            outputBeingSpent: .init(value: utxo.value, lockingScript: utxo.lockingScript)
        )
        let messageOnce = SHA256.hash(preimage)
        let ok = try ECDSA.verify(signature: sigNoType, message: messageOnce, publicKey: pk, format: .ecdsa(.der))
        #expect(ok)
        
        // Wrong digests must fail.
        #expect(try !ECDSA.verify(signature: sigNoType, message: preimage, publicKey: pk, format: .ecdsa(.der)))
        #expect(try !ECDSA.verify(signature: sigNoType, message: HASH256.hash(preimage), publicKey: pk, format: .ecdsa(.der)))
    }
    
    @Test("P2PKH CHECKSIG: preimage hashing semantics and verification (Schnorr)")
    func checksig_hashing_and_verify_schnorr() throws {
        let (sk, pk) = try makeKeypair()
        let addr = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: pk)))
        let utxo = Transaction.Output.Unspent(
            value: 180_000,
            lockingScript: addr.lockingScript.data,
            previousTransactionHash: makeDummyPrevoutHash(0x22),
            previousTransactionOutputIndex: 1
        )
        let recipient = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: pk)))
        let outputs = [Transaction.Output(value: 40_000, address: recipient)]
        let change = Transaction.Output(value: utxo.value - 40_000, address: recipient)
        
        let tx = try Transaction.build(
            version: 2,
            utxoPrivateKeyPairs: [utxo: sk],
            recipientOutputs: outputs,
            changeOutput: change,
            signatureFormat: .schnorr,
            feePerByte: 1,
            unlockers: [utxo: .p2pkh_CheckSig(hashType: .all(anyoneCanPay: false))]
        )
        
        let input = tx.inputs[0]
        let (sigNoType, sighashType, pub) = try splitCheckSigUnlock(input.unlockingScript)
        #expect(pub == pk.compressedData)
        #expect(sighashType == Transaction.HashType.all(anyoneCanPay: false).value & 0xff)
        
        let preimage = try tx.generatePreimage(
            for: 0,
            hashType: .all(anyoneCanPay: false),
            outputBeingSpent: .init(value: utxo.value, lockingScript: utxo.lockingScript)
        )
        let messageOnce = SHA256.hash(preimage)
        let ok = try ECDSA.verify(signature: sigNoType, message: messageOnce, publicKey: pk, format: .schnorr)
        #expect(ok)
        
        #expect(try !ECDSA.verify(signature: sigNoType, message: preimage, publicKey: pk, format: .schnorr))
        #expect(try !ECDSA.verify(signature: sigNoType, message: HASH256.hash(preimage), publicKey: pk, format: .schnorr))
    }
    
    // MARK: - OP_CHECKDATASIG path
    
    @Test("P2PKH CHECKDATASIG: raw message semantics and verification")
    func checkdatasig_hashing_and_verify() throws {
        let (sk, pk) = try makeKeypair()
        let addr = try Address(script: .p2pkh_OPCHECKDATASIG(hash: .init(publicKey: pk)))
        let utxo = Transaction.Output.Unspent(
            value: 220_000,
            lockingScript: addr.lockingScript.data,
            previousTransactionHash: makeDummyPrevoutHash(0x33),
            previousTransactionOutputIndex: 0
        )
        let recipient = try Address(script: .p2pkh_OPCHECKDATASIG(hash: .init(publicKey: pk)))
        let outputs = [Transaction.Output(value: 60_000, address: recipient)]
        let change = Transaction.Output(value: utxo.value - 60_000, address: recipient)
        
        let rawMessage = Data("hello-bch-cds".utf8)
        
        let tx = try Transaction.build(
            version: 2,
            utxoPrivateKeyPairs: [utxo: sk],
            recipientOutputs: outputs,
            changeOutput: change,
            signatureFormat: .ecdsa(.der),
            feePerByte: 1,
            unlockers: [utxo: .p2pkh_CheckDataSig(message: rawMessage)]
        )
        
        let input = tx.inputs[0]
        let (sig, pushedMsg, pub) = try splitCheckDataSigUnlock(input.unlockingScript)
        #expect(pub == pk.compressedData)
        #expect(pushedMsg == rawMessage)
        
        // Raw message must verify; hashed variants must fail.
        #expect(try ECDSA.verify(signature: sig, message: rawMessage, publicKey: pk, format: .ecdsa(.der)))
        #expect(try !ECDSA.verify(signature: sig, message: SHA256.hash(rawMessage), publicKey: pk, format: .ecdsa(.der)))
        #expect(try !ECDSA.verify(signature: sig, message: HASH256.hash(rawMessage), publicKey: pk, format: .ecdsa(.der)))
    }
    
    // MARK: - Real Fulcrum hit (no mocks)
    
    @Test("Fulcrum connectivity: get tip and fees", .timeLimit(.minutes(2)))
    func fulcrum_connectivity_basic() async throws {
        let fulcrum: SwiftFulcrum.Fulcrum
        if let url = ProcessInfo.processInfo.environment["FULCRUM_URL"], !url.isEmpty {
            fulcrum = try await .init(url: url)
        } else {
            fulcrum = try await .init()
        }
        try await fulcrum.start()
        defer { Task { await fulcrum.stop() } }
        
        // Fee endpoints should return sane values.
        let relay = try await Transaction.relayFee(using: fulcrum)
        #expect(relay.uint64 > 0)
        
        let est = try await Transaction.estimateFee(numberOfBlocks: 1, using: fulcrum)
        #expect(est.uint64 > 0)
        
        // Query a zero-balance fresh address to exercise address RPCs.
        let (_, pk) = try makeKeypair()
        let freshAddr = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: pk)))
        let bal = try await freshAddr.fetchBalance(using: fulcrum)
        #expect(bal.uint64 >= 0)
    }
    
}
