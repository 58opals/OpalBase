// DataExtensionsValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Data extensions", .tags(.unit))
struct DataExtensionsValidator {
    @Test("reversedData matches reverse iteration")
    func reversedDataMatchesStandardReverse() throws {
        let bytes = Array(0...255).map(UInt8.init)
        let data = Data(bytes)
        
        let reversed = data.reversedData
        let expected = Data(bytes.reversed())
        
        #expect(reversed == expected)
    }
    
    @Test("hexadecimal initializer decodes valid strings")
    func hexadecimalInitializerDecodesValidStrings() throws {
        let lowercaseHexadecimal = "deadbeef"
        let prefixedUppercaseHexadecimal = "0xCAFEBABE"
        
        let lowercaseData = try Data(hexadecimalString: lowercaseHexadecimal)
        let prefixedUppercaseData = try Data(hexadecimalString: prefixedUppercaseHexadecimal)
        
        #expect(lowercaseData == Data([0xde, 0xad, 0xbe, 0xef]))
        #expect(prefixedUppercaseData == Data([0xca, 0xfe, 0xba, 0xbe]))
    }
    
    @Test("hexadecimal initializer rejects malformed strings")
    func hexadecimalInitializerRejectsMalformedStrings() {
        #expect(throws: Data.Error.cannotConvertHexadecimalStringToData) {
            _ = try Data(hexadecimalString: "0x123g")
        }
        
        #expect(throws: Data.Error.cannotConvertHexadecimalStringToData) {
            _ = try Data(hexadecimalString: "abc")
        }
    }

    @Test("reader rejects negative read lengths")
    func readerRejectsNegativeReadLengths() {
        var reader = Data.ReaderModel(Data([0x01, 0x02, 0x03]))

        #expect(throws: Data.ReaderModel.Error.negativeReadCount(-1)) {
            _ = try reader.readData(count: -1)
        }
    }
}
