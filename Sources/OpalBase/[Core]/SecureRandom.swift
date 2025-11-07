// SecureRandom.swift

import Foundation
import Security

enum SecureRandom {
    enum Error: Swift.Error, Equatable, Sendable {
        case failed(status: Int32)
    }
    
    static func makeBytes(count: Int) throws -> [UInt8] {
        precondition(count >= 0)
        guard count > 0 else { return [] }
        
        var bytes = [UInt8](repeating: 0, count: count)
        
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw Error.failed(status: status)
        }
        
        return bytes
    }
}
