import Foundation

extension Address.Book {
    enum Error: Swift.Error {
        case indexOutOfBounds
        case privateKeyNotFound
        case addressIsNotFoundInAddressBook
        case addressIsDuplicated
    }
}
