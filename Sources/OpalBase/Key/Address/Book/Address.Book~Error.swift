import Foundation

extension Address.Book {
    enum Error: Swift.Error {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case privateKeyDuplicated
        case addressDuplicated
        case entryDuplicated
        
        case insufficientFunds
    }
}
