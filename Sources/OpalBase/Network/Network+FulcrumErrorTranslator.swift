// Network+FulcrumErrorTranslator.swift

import Foundation
import SwiftFulcrum

extension Network {
    enum FulcrumErrorTranslator {
        static func translate(_ error: Swift.Error) -> Network.Failure {
            if let failure = error as? Network.Failure { return failure }
            
            if error is CancellationError {
                return Network.Failure(reason: .cancelled, message: "Operation cancelled")
            }
            
            guard let fulcrumError = error as? Fulcrum.Error else {
                return Network.Failure(reason: .unknown, message: error.localizedDescription)
            }
            
            switch fulcrumError {
            case .transport(let transport):
                return translateTransport(transport)
            case .rpc(let server):
                return Network.Failure(
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
        
        private static func translateTransport(_ transport: Fulcrum.Error.Transport) -> Network.Failure {
            switch transport {
            case .setupFailed:
                return Network.Failure(reason: .transport, message: "Failed to create transport")
            case .connectionClosed(let code, let reason):
                return Network.Failure(
                    reason: .transport,
                    message: reason ?? "Connection closed",
                    metadata: ["closeCode": String(code.rawValue)]
                )
            case .network(let networkError):
                return Network.Failure(reason: .network, message: networkError.localizedDescription)
            case .reconnectFailed:
                return Network.Failure(reason: .transport, message: "Reconnection attempts exhausted")
            case .heartbeatTimeout:
                return Network.Failure(reason: .timeout, message: "Heartbeat timed out")
            }
        }
        
        private static func translateCoding(_ coding: Fulcrum.Error.Coding) -> Network.Failure {
            switch coding {
            case .encode(let underlying):
                return Network.Failure(reason: .encoding, message: underlying?.localizedDescription)
            case .decode(let underlying):
                return Network.Failure(reason: .decoding, message: underlying?.localizedDescription)
            }
        }
        
        private static func translateClient(_ client: Fulcrum.Error.Client) -> Network.Failure {
            switch client {
            case .urlNotFound:
                return Network.Failure(reason: .transport, message: "No server URL available")
            case .invalidURL(let string):
                return Network.Failure(reason: .transport, message: "Invalid server URL: \(string)")
            case .duplicateHandler:
                return Network.Failure(reason: .unknown, message: "Duplicate handler registered")
            case .cancelled:
                return Network.Failure(reason: .cancelled, message: "Operation cancelled")
            case .timeout(let duration):
                return Network.Failure(
                    reason: .timeout,
                    message: "Operation timed out",
                    metadata: ["timeoutSeconds": String(duration.totalSeconds)]
                )
            case .emptyResponse:
                return Network.Failure(reason: .protocolViolation, message: "Empty response from server")
            case .protocolMismatch(let message):
                return Network.Failure(reason: .protocolViolation, message: message)
            case .unknown(let underlying):
                return Network.Failure(reason: .unknown, message: underlying?.localizedDescription)
            }
        }
    }
}
