import Foundation

extension Address.Book {
    enum Error: Swift.Error {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case addressDuplicated
        
        case insufficientFunds
    }
}
