// Log.swift

import Foundation

public actor Log {
    public static let shared = Log()
    public var isEnabled: Bool = false
    
    public func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print(message())
    }
}
