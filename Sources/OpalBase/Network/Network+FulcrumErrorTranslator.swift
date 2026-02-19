// Network+FulcrumErrorTranslator.swift

import Foundation
import SwiftFulcrum

extension Network {
    static func performWithFailureTranslation<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch {
            throw FulcrumErrorTranslator.translate(error)
        }
    }
    
    static func checkFailureEquivalence(_ left: Swift.Error, _ right: Swift.Error) -> Bool {
        FulcrumErrorTranslator.checkFailureEquivalence(left, right)
    }
    
    enum FulcrumErrorTranslator {
        private static func describe(_ error: Swift.Error?) -> String? {
            guard let error else { return nil }
            return String(describing: error)
        }
        
        static func translate(_ error: Swift.Error) -> Network.Error {
            if let failure = error as? Network.Error { return failure }
            
            if let dataError = error as? Data.Error {
                return Network.Error(reason: .decoding, message: describe(dataError))
            }
            
            if let decodingError = error as? DecodingError {
                return Network.Error(reason: .decoding, message: String(describing: decodingError))
            }
            
            if let encodingError = error as? EncodingError {
                return Network.Error(reason: .encoding, message: String(describing: encodingError))
            }
            
            if error is CancellationError {
                return Network.Error(reason: .cancelled, message: "Operation cancelled")
            }
            
            guard let fulcrumError = error as? SwiftFulcrum.FulcrumClient.Error else {
                return Network.Error(reason: .unknown, message: String(describing: error))
            }
            
            switch fulcrumError {
            case .transport(let transport):
                return translateTransport(transport)
            case .rpc(let server):
                return Network.Error(
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
            if let failure = error as? Network.Error { return failure.reason == .cancelled }
            if let fulcrumError = error as? SwiftFulcrum.FulcrumClient.Error,
               case .client(.cancelled) = fulcrumError {
                return true
            }
            return false
        }
        
        private static func translateTransport(_ transport: SwiftFulcrum.FulcrumClient.Error.TransportModel) -> Network.Error {
            switch transport {
            case .setupFailed:
                return Network.Error(reason: .transport, message: "Failed to create transport")
            case .connectionClosed(let code, let reason):
                return Network.Error(
                    reason: .transport,
                    message: reason ?? "Connection closed",
                    metadata: ["closeCode": String(code.rawValue)]
                )
            case .network(let networkError):
                return translateNetwork(networkError)
            case .reconnectFailed:
                return Network.Error(reason: .transport, message: "Reconnection attempts exhausted")
            case .heartbeatTimeout:
                return Network.Error(reason: .timeout, message: "Heartbeat timed out")
            }
        }
        
        private static func translateNetwork(_ network: SwiftFulcrum.FulcrumClient.Error.NetworkModel) -> Network.Error {
            switch network {
            case .tlsNegotiationFailed(let underlying):
                return Network.Error(
                    reason: .network,
                    message: underlying?.localizedDescription ?? "TLS negotiation failed"
                )
            }
        }
        
        private static func translateCoding(_ coding: SwiftFulcrum.FulcrumClient.Error.CodingModel) -> Network.Error {
            switch coding {
            case .encode(let underlying):
                return Network.Error(reason: .encoding, message: describe(underlying))
            case .decode(let underlying):
                return Network.Error(reason: .decoding, message: describe(underlying))
            }
        }
        
        private static func translateClient(_ client: SwiftFulcrum.FulcrumClient.Error.Client) -> Network.Error {
            switch client {
            case .urlNotFound:
                return Network.Error(reason: .transport, message: "No server URL available")
            case .invalidURL(let string):
                return Network.Error(reason: .transport, message: "Invalid server URL: \(string)")
            case .duplicateHandler:
                return Network.Error(reason: .unknown, message: "Duplicate handler registered")
            case .cancelled:
                return Network.Error(reason: .cancelled, message: "Operation cancelled")
            case .timeout(let duration):
                return Network.Error(
                    reason: .timeout,
                    message: "Operation timed out",
                    metadata: ["timeoutSeconds": String(duration.totalSeconds)]
                )
            case .emptyResponse(let identifier):
                return Network.Error(reason: .protocolViolation,
                                       message: "Empty response from server",
                                       metadata: identifier.map { ["requestIdentifier": $0.uuidString] } ?? .init())
            case .protocolMismatch(let message):
                return Network.Error(reason: .protocolViolation, message: message)
            case .unknown(let underlying):
                guard let underlying else {
                    return Network.Error(reason: .unknown, message: nil)
                }
                
                if underlying is DecodingError {
                    return Network.Error(reason: .decoding, message: describe(underlying))
                }
                
                let cocoaError = underlying as NSError
                if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == 3840 {
                    return Network.Error(reason: .decoding, message: describe(underlying))
                }
                
                return Network.Error(reason: .unknown, message: describe(underlying))
            }
        }
    }
}

extension Swift.Error {
    var isCancellationError: Bool {
        Network.FulcrumErrorTranslator.checkCancellation(self)
    }
}
