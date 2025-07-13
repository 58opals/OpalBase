// Log.swift

import Foundation

actor Log {
    static let shared = Log()
    var isEnabled: Bool = false
    
    func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print(message())
    }
}
