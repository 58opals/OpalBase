// Network+FulcrumSession.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumSession {
        public enum Error: Swift.Error {
            case sessionAlreadyStarted
            case sessionNotStarted
        }
        
        public let configuration: SwiftFulcrum.Fulcrum.Configuration
        public let serverAddress: URL?
        
        private let fulcrum: SwiftFulcrum.Fulcrum
        private var isSessionRunning = false
        
        public init(serverAddress: URL? = nil,
                    configuration: SwiftFulcrum.Fulcrum.Configuration = .init()) async throws {
            let fulcrum = try await SwiftFulcrum.Fulcrum(url: serverAddress?.absoluteString,
                                                         configuration: configuration)
            self.configuration = configuration
            self.serverAddress = serverAddress
            self.fulcrum = fulcrum
        }
        
        public var isRunning: Bool { isSessionRunning }
        
        public func start() async throws {
            guard !isSessionRunning else { return }
            
            try await fulcrum.start()
            isSessionRunning = true
        }
        
        public func stop() async {
            guard isSessionRunning else { return }
            
            await fulcrum.stop()
            isSessionRunning = false
        }
        
        public func reconnect() async throws {
            try ensureSessionIsRunning()
            try await fulcrum.reconnect()
        }
        
        public func submit<RegularResponseResult: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            responseType: RegularResponseResult.Type = RegularResponseResult.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> SwiftFulcrum.Fulcrum.RPCResponse<RegularResponseResult, Never> {
            try ensureSessionIsRunning()
            return try await fulcrum.submit(method: method,
                                            responseType: responseType,
                                            options: options)
        }
        
        public func submit<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            initialType: Initial.Type = Initial.self,
            notificationType: Notification.Type = Notification.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> SwiftFulcrum.Fulcrum.RPCResponse<Initial, Notification> {
            try ensureSessionIsRunning()
            return try await fulcrum.submit(method: method,
                                            initialType: initialType,
                                            notificationType: notificationType,
                                            options: options)
        }
        
        private func ensureSessionIsRunning() throws {
            guard isSessionRunning else { throw Error.sessionNotStarted }
        }
    }
}
