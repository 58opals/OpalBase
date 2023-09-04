// Opal Base by 58 Opals

import Foundation

protocol Address {}

enum AddressError: Error {
    case failed(_ string: String)
    case invalid(_ string: String)
}
