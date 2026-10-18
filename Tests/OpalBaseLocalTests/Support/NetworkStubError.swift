// NetworkStubError.swift

import Foundation
@testable import OpalBase
@testable import OpalBaseCore

enum NetworkStubError: Swift.Error, Equatable {
    case forced(String)
}
