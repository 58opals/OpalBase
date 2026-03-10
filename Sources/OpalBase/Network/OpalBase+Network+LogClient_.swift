// OpalBase+Network+LogClient_.swift

import Foundation

extension _OpalBase.Network {
    protocol LogClient: Sendable {
        func log(_ level: LogLevel,
                 _ message: @autoclosure () -> String,
                 metadata: [String: String]?,
                 file: String,
                 function: String,
                 line: UInt)
    }
}
