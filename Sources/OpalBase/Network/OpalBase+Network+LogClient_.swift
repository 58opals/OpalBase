// OpalBase+Network+LogClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol LogClient: Sendable {
        func log(_ level: LogLevelModel,
                 _ message: @autoclosure () -> String,
                 metadata: [String: String]?,
                 file: String,
                 function: String,
                 line: UInt)
    }
}
