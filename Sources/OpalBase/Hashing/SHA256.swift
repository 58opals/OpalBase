// SHA256.swift

import Foundation
import CryptoKit

struct SHA256 {
    static func hash(_ data: Data) -> Data {
        let digest = CryptoKit.SHA256.hash(data: data)
        return .init(digest)
    }
}
