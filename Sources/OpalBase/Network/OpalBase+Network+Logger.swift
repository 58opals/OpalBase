// OpalBase+Network+Logger.swift

import Foundation

extension _OpalBase.Network {
    public struct Logger: Sendable {
        private let logHandler: @Sendable (LogLevel, String, [String: String]?, String, String, UInt) -> Void

        public init(
            log: @escaping @Sendable (LogLevel, String, [String: String]?, String, String, UInt) -> Void = { _, _, _, _, _, _ in }
        ) {
            self.logHandler = log
        }

        public func log(_ level: LogLevel,
                        _ message: @autoclosure () -> String,
                        metadata: [String: String]?,
                        file: String,
                        function: String,
                        line: UInt) {
            logHandler(level, message(), metadata, file, function, line)
        }
    }
}
