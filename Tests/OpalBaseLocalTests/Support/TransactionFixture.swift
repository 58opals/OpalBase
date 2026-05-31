// TransactionFixture.swift

import Foundation
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

struct TransactionFixture {
    let transactionHash: OpalBase.Transaction.Hash
    let rawTransactionData: Data
    let rawTransactionHexadecimal: String
    let verboseResponse: SwiftFulcrum.Response.Blockchain.Transaction.Verbose
    let blockHashData: Data
    let blockTime: UInt32
    let confirmations: UInt32
    let transactionTime: UInt32

    static func make() throws -> TransactionFixture {
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0x01, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 546, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        let rawTransactionHexadecimal = rawTransactionData.hexadecimalString
        let blockHashData = Data(repeating: 0xaa, count: 32)
        let blockHashHexadecimal = blockHashData.hexadecimalString
        let blockTime: UInt32 = 1_710_000_000
        let confirmations: UInt32 = 12
        let transactionTime: UInt32 = 1_710_000_100
        let verboseResponse = try makeVerboseResponse(
            transactionHash: transactionHash.reverseOrder.hexadecimalString,
            rawTransactionHexadecimal: rawTransactionHexadecimal,
            blockHashHexadecimal: blockHashHexadecimal,
            blockTime: blockTime,
            confirmations: confirmations,
            transactionTime: transactionTime,
            size: rawTransactionData.count
        )

        return TransactionFixture(
            transactionHash: transactionHash,
            rawTransactionData: rawTransactionData,
            rawTransactionHexadecimal: rawTransactionHexadecimal,
            verboseResponse: verboseResponse,
            blockHashData: blockHashData,
            blockTime: blockTime,
            confirmations: confirmations,
            transactionTime: transactionTime
        )
    }

    static func makeVerboseResponse(
        transactionHash: String,
        rawTransactionHexadecimal: String,
        blockHashHexadecimal: String?,
        blockTime: UInt32?,
        confirmations: UInt32?,
        transactionTime: UInt32?,
        size: Int
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Verbose {
        try makeVerboseResponseWithUnsignedMetadata(
            transactionHash: transactionHash,
            rawTransactionHexadecimal: rawTransactionHexadecimal,
            blockHashHexadecimal: blockHashHexadecimal,
            blockTime: blockTime.map(UInt.init),
            confirmations: confirmations.map(UInt.init),
            transactionTime: transactionTime.map(UInt.init),
            size: size
        )
    }

    static func makeVerboseResponseWithUnsignedMetadata(
        transactionHash: String,
        rawTransactionHexadecimal: String,
        blockHashHexadecimal: String?,
        blockTime: UInt?,
        confirmations: UInt?,
        transactionTime: UInt?,
        size: Int
    ) throws -> SwiftFulcrum.Response.Blockchain.Transaction.Verbose {
        var payload: [String: Any] = [
            "hash": transactionHash,
            "hex": rawTransactionHexadecimal,
            "locktime": 0,
            "size": size,
            "txid": transactionHash,
            "version": 2,
            "vin": [
                [
                    "scriptSig": [
                        "asm": "",
                        "hex": ""
                    ],
                    "sequence": UInt32.max,
                    "txid": String(repeating: "1", count: 64),
                    "vout": 0
                ]
            ],
            "vout": [
                [
                    "n": 0,
                    "scriptPubKey": [
                        "addresses": ["bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"],
                        "asm": "1",
                        "hex": "51",
                        "reqSigs": 1,
                        "type": "pubkeyhash"
                    ],
                    "value": 0.00000546
                ]
            ]
        ]
        if let blockHashHexadecimal {
            payload["blockhash"] = blockHashHexadecimal
        }
        if let blockTime {
            payload["blocktime"] = blockTime
        }
        if let confirmations {
            payload["confirmations"] = confirmations
        }
        if let transactionTime {
            payload["time"] = transactionTime
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.Transaction.Verbose.self,
            from: payloadData
        )
    }
}
