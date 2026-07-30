// ReusablePaymentAddressClientTestActor.swift

import SwiftFulcrum
@testable import OpalBase

actor ReusablePaymentAddressClientTestActor:
    OpalBase.Network.Fulcrum.ReusablePaymentAddressClient
{
    private let historyResponse:
        SwiftFulcrum.Response.Blockchain.RPA.History
    private let mempoolResponse:
        SwiftFulcrum.Response.Blockchain.RPA.Mempool
    private let historyFailure: (any Swift.Error & Sendable)?
    private let mempoolFailure: (any Swift.Error & Sendable)?

    private var historyRequest:
        (
            prefix: String,
            fromHeight: UInt,
            toHeight: UInt?,
            timeout: Duration?
        )?
    private var mempoolRequest:
        (prefix: String, timeout: Duration?)?

    init(
        historyResponse: SwiftFulcrum.Response.Blockchain.RPA.History,
        mempoolResponse: SwiftFulcrum.Response.Blockchain.RPA.Mempool,
        historyFailure: (any Swift.Error & Sendable)? = nil,
        mempoolFailure: (any Swift.Error & Sendable)? = nil
    ) {
        self.historyResponse = historyResponse
        self.mempoolResponse = mempoolResponse
        self.historyFailure = historyFailure
        self.mempoolFailure = mempoolFailure
    }

    func fetchReusablePaymentAddressHistory(
        prefix: String,
        fromHeight: UInt,
        toHeight: UInt?,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.RPA.History {
        historyRequest = (
            prefix,
            fromHeight,
            toHeight,
            options.timeout
        )
        if let historyFailure {
            throw historyFailure
        }
        return historyResponse
    }

    func fetchReusablePaymentAddressMempool(
        prefix: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.RPA.Mempool {
        mempoolRequest = (prefix, options.timeout)
        if let mempoolFailure {
            throw mempoolFailure
        }
        return mempoolResponse
    }

    func readHistoryRequest()
        -> (
            prefix: String,
            fromHeight: UInt,
            toHeight: UInt?,
            timeout: Duration?
        )?
    {
        historyRequest
    }

    func readMempoolRequest()
        -> (prefix: String, timeout: Duration?)?
    {
        mempoolRequest
    }
}
