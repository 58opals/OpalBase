// NetworkStubError.swift

import Foundation
@testable import OpalBase

enum NetworkStubError: Swift.Error, Equatable {
    case forced(String)
}
