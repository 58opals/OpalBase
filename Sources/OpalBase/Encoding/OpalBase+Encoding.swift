// OpalBase+Encoding.swift

import Foundation

extension OpalBase {
    public enum Encoding {}
}

extension _OpalBase.Encoding {
    public enum Error: Swift.Error, Equatable {
        case invalidHexadecimalString
    }

    public static func data(fromHexadecimal hexadecimalString: String) throws -> Data {
        do {
            return try Data(hexadecimalString: hexadecimalString)
        } catch {
            throw Error.invalidHexadecimalString
        }
    }

    public static func hexadecimalString(from data: Data) -> String {
        data.hexadecimalString
    }
}
