// NetworkModel+FulcrumErrorTranslatorModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    static func performWithFailureTranslation<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            throw FulcrumErrorTranslatorModel.translate(error)
        }
    }
    
    static func checkFailureEquivalence(_ left: Swift.Error, _ right: Swift.Error) -> Bool {
        FulcrumErrorTranslatorModel.checkFailureEquivalence(left, right)
    }
    
    enum FulcrumErrorTranslatorModel {
        private static func describe(_ error: Swift.Error?) -> String? {
            guard let error else { return nil }
            return String(describing: error)
        }
        
        static func translate(_ error: Swift.Error) -> NetworkModel.Error {
            if let failure = error as? NetworkModel.Error { return failure }
            
            if let dataError = error as? Data.Error {
                return NetworkModel.Error(reason: .decoding, message: describe(dataError))
            }
            
            if let decodingError = error as? DecodingError {
                return NetworkModel.Error(reason: .decoding, message: String(describing: decodingError))
            }
            
            if let encodingError = error as? EncodingError {
                return NetworkModel.Error(reason: .encoding, message: String(describing: encodingError))
            }
            
            if error is CancellationError {
                return NetworkModel.Error(reason: .cancelled, message: "OperationModel cancelled")
            }
            
            guard let fulcrumError = error as? SwiftFulcrum.FulcrumClient.Error else {
                return NetworkModel.Error(reason: .unknown, message: String(describing: error))
            }
            
            switch fulcrumError {
            case .transport(let transport):
                return translateTransport(transport)
            case .rpc(let server):
                return NetworkModel.Error(
                    reason: .server(code: server.code),
                    message: server.message,
                    metadata: ["serverIdentifier": server.id?.uuidString ?? "unknown"]
                )
            case .coding(let coding):
                return translateCoding(coding)
            case .client(let clientError):
                return translateClient(clientError)
            }
        }
        
        static func checkFailureEquivalence(_ left: Swift.Error, _ right: Swift.Error) -> Bool {
            translate(left) == translate(right)
        }
        
        static func checkCancellation(_ error: Swift.Error) -> Bool {
            if error is CancellationError { return true }
            if let failure = error as? NetworkModel.Error { return failure.reason == .cancelled }
            if let fulcrumError = error as? SwiftFulcrum.FulcrumClient.Error,
               case .client(.cancelled) = fulcrumError {
                return true
            }
            return false
        }
        
        private static func translateTransport(_ transport: SwiftFulcrum.FulcrumClient.Error.TransportModel) -> NetworkModel.Error {
            switch transport {
            case .setupFailed:
                return NetworkModel.Error(reason: .transport, message: "Failed to create transport")
            case .connectionClosed(let code, let reason):
                return NetworkModel.Error(
                    reason: .transport,
                    message: reason ?? "Connection closed",
                    metadata: ["closeCode": String(code.rawValue)]
                )
            case .network(let networkError):
                return translateNetwork(networkError)
            case .reconnectFailed:
                return NetworkModel.Error(reason: .transport, message: "Reconnection attempts exhausted")
            case .heartbeatTimeout:
                return NetworkModel.Error(reason: .timeout, message: "Heartbeat timed out")
            }
        }
        
        private static func translateNetwork(_ network: SwiftFulcrum.FulcrumClient.Error.NetworkModel) -> NetworkModel.Error {
            switch network {
            case .tlsNegotiationFailed(let underlying):
                return NetworkModel.Error(
                    reason: .network,
                    message: underlying?.localizedDescription ?? "TLS negotiation failed"
                )
            }
        }
        
        private static func translateCoding(_ coding: SwiftFulcrum.FulcrumClient.Error.CodingModel) -> NetworkModel.Error {
            switch coding {
            case .encode(let underlying):
                return NetworkModel.Error(reason: .encoding, message: describe(underlying))
            case .decode(let underlying):
                return NetworkModel.Error(reason: .decoding, message: describe(underlying))
            }
        }
        
        private static func translateClient(_ client: SwiftFulcrum.FulcrumClient.Error.Client) -> NetworkModel.Error {
            switch client {
            case .urlNotFound:
                return NetworkModel.Error(reason: .transport, message: "No server URL available")
            case .invalidURL(let string):
                return NetworkModel.Error(reason: .transport, message: "Invalid server URL: \(string)")
            case .duplicateHandler:
                return NetworkModel.Error(reason: .unknown, message: "Duplicate handler registered")
            case .cancelled:
                return NetworkModel.Error(reason: .cancelled, message: "OperationModel cancelled")
            case .timeout(let duration):
                return NetworkModel.Error(
                    reason: .timeout,
                    message: "OperationModel timed out",
                    metadata: ["timeoutSeconds": String(duration.totalSeconds)]
                )
            case .emptyResponse(let identifier):
                return NetworkModel.Error(reason: .protocolViolation,
                                       message: "Empty response from server",
                                       metadata: identifier.map { ["requestIdentifier": $0.uuidString] } ?? .init())
            case .protocolMismatch(let message):
                return NetworkModel.Error(reason: .protocolViolation, message: message)
            case .invalidProtocolNegotiationRange(minimumVersion: let min, maximumVersion: let max):
                return NetworkModel.Error(
                    reason: .protocolViolation,
                    message: "Invalid protocol negotiation range",
                    metadata: [
                        "minimumVersion": min.description,
                        "maximumVersion": max.description
                    ]
                )
            case .unknown(let underlying):
                guard let underlying else {
                    return NetworkModel.Error(reason: .unknown, message: nil)
                }
                
                if underlying is DecodingError {
                    return NetworkModel.Error(reason: .decoding, message: describe(underlying))
                }
                
                let cocoaError = underlying as NSError
                if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == 3840 {
                    return NetworkModel.Error(reason: .decoding, message: describe(underlying))
                }
                
                return NetworkModel.Error(reason: .unknown, message: describe(underlying))
            }
        }
    }
}

extension Swift.Error {
    var isCancellationError: Bool {
        NetworkModel.FulcrumErrorTranslatorModel.checkCancellation(self)
    }
}
